locals {
  arn = "aws"
}

resource "aws_iam_instance_profile" "master" {
  name = "${var.cluster_id}-master-profile"

  role = "${aws_iam_role.master_role.name}"
}

resource "aws_iam_role" "master_role" {
  name = "${var.cluster_id}-master-role"
  path = "/"

  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": "sts:AssumeRole",
            "Principal": {
                "Service": "ec2.amazonaws.com"
            },
            "Effect": "Allow",
            "Sid": ""
        }
    ]
}
EOF

  tags = "${merge(map(
    "Name", "${var.cluster_id}-master-role",
  ), var.tags)}"
}

resource "aws_iam_role_policy" "master_policy" {
  name = "${var.cluster_id}-master-policy"
  role = "${aws_iam_role.master_role.id}"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "ec2:*",
      "Resource": "*",
      "Effect": "Allow"
    },
    {
      "Action": "iam:PassRole",
      "Resource": "*",
      "Effect": "Allow"
    },
    {
      "Action" : [
        "s3:GetObject"
      ],
      "Resource": "arn:${local.arn}:s3:::*",
      "Effect": "Allow"
    },
    {
      "Action": "elasticloadbalancing:*",
      "Resource": "*",
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_network_interface" "master" {
  count     = "${var.instance_count}"
  subnet_id = "${var.az_to_subnet_id[var.availability_zones[count.index]]}"

  security_groups = ["${var.master_sg_ids}"]

  tags = "${merge(map(
    "Name", "${var.cluster_id}-master-${count.index}",
  ), var.tags)}"
}

resource "aws_instance" "master" {
  count = "${var.instance_count}"
  ami   = "${var.ec2_ami}"

  iam_instance_profile = "${aws_iam_instance_profile.master.name}"
  instance_type        = "${var.instance_type}"
  user_data            = "${var.user_data_ign}"

  network_interface {
    network_interface_id = "${aws_network_interface.master.*.id[count.index]}"
    device_index         = 0
  }

  lifecycle {
    # Ignore changes in the AMI which force recreation of the resource. This
    # avoids accidental deletion of nodes whenever a new CoreOS Release comes
    # out.
    ignore_changes = ["ami"]
  }

  tags = "${merge(map(
    "Name", "${var.cluster_id}-master-${count.index}",
  ), var.tags)}"

  root_block_device {
    volume_type = "${var.root_volume_type}"
    volume_size = "${var.root_volume_size}"
    iops        = "${var.root_volume_type == "io1" ? var.root_volume_iops : 0}"
  }

  volume_tags = "${merge(map(
    "Name", "${var.cluster_id}-master-${count.index}-vol",
  ), var.tags)}"
}

resource "aws_lb_target_group_attachment" "master" {
  count = "${var.instance_count * var.target_group_arns_length}"

  target_group_arn = "${var.target_group_arns[count.index % var.target_group_arns_length]}"
  target_id        = "${aws_instance.master.*.private_ip[count.index / var.target_group_arns_length]}"
}
