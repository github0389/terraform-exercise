provider "aws" {
  region = "${var.region}"
}

resource "aws_vpc" "vpc" {
  cidr_block           = "${var.vpc-cidr}"
  enable_dns_hostnames = true
}

# Public Subnets
resource "aws_subnet" "subnet-a" {
  vpc_id            = "${aws_vpc.vpc.id}"
  cidr_block        = "${var.subnet-cidr-a}"
  availability_zone = "${var.region}a"
}

resource "aws_subnet" "subnet-b" {
  vpc_id            = "${aws_vpc.vpc.id}"
  cidr_block        = "${var.subnet-cidr-b}"
  availability_zone = "${var.region}b"
}

resource "aws_subnet" "subnet-c" {
  vpc_id            = "${aws_vpc.vpc.id}"
  cidr_block        = "${var.subnet-cidr-c}"
  availability_zone = "${var.region}c"
}

resource "aws_subnet" "subnet-d" {
  count = "${var.region == "us-east-1" ? 1 : 0}"

  vpc_id            = "${aws_vpc.vpc.id}"
  cidr_block        = "${var.subnet-cidr-d}"
  availability_zone = "${var.region}d"
}

resource "aws_route_table" "subnet-route-table" {
  vpc_id = "${aws_vpc.vpc.id}"
}

resource "aws_internet_gateway" "igw" {
  vpc_id = "${aws_vpc.vpc.id}"
}

resource "aws_route" "subnet-route" {
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.igw.id}"
  route_table_id         = "${aws_route_table.subnet-route-table.id}"
}

resource "aws_route_table_association" "subnet-a-route-table-association" {
  subnet_id      = "${aws_subnet.subnet-a.id}"
  route_table_id = "${aws_route_table.subnet-route-table.id}"
}

resource "aws_route_table_association" "subnet-b-route-table-association" {
  subnet_id      = "${aws_subnet.subnet-b.id}"
  route_table_id = "${aws_route_table.subnet-route-table.id}"
}

resource "aws_route_table_association" "subnet-c-route-table-association" {
  subnet_id      = "${aws_subnet.subnet-c.id}"
  route_table_id = "${aws_route_table.subnet-route-table.id}"
}

resource "aws_route_table_association" "subnet-d-route-table-association" {
  count = "${var.region == "us-east-1" ? 1 : 0}"

  subnet_id      = "${element(aws_subnet.subnet-d.*.id, count.index)}"
  route_table_id = "${aws_route_table.subnet-route-table.id}"
}

# Nginx

data "aws_ami" "centos" {
  most_recent = true
  owners      = ["679593333241"]

  filter {
    name   = "product-code"
    values = ["aw0evgkw8e5c1q413zgy5pjce"]
  }

  filter {
    name   = "description"
    values = ["CentOS Linux 7 x86_64 HVM EBS ENA*"]
  }
}

resource "aws_instance" "bastion" {
  ami                         = "${data.aws_ami.centos.id}"
  instance_type               = "t2.small"
  vpc_security_group_ids      = ["${module.sg_ec2_bastion.this_security_group_id}"]
  subnet_id                   = "${aws_subnet.subnet-a.id}"
  associate_public_ip_address = true
}

resource "aws_instance" "instance" {
  count = "${var.instance-count}"

  ami                         = "${data.aws_ami.centos.id}"
  instance_type               = "t2.small"
  vpc_security_group_ids      = ["${module.sg_ec2_nginx.this_security_group_id}"]
  subnet_id                   = "${aws_subnet.subnet-a.id}"
  associate_public_ip_address = true

  user_data = <<EOF
#!/bin/sh
yum install -y epel-release
yum install -y nginx
service nginx start
EOF
}

module "sg_ec2_bastion" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "2.16.0"

  name        = "ec2-bastion"
  description = "Bastion Security Group"
  vpc_id      = "${aws_vpc.vpc.id}"

  ingress_with_cidr_blocks = [
    {
      rule        = "ssh-tcp"
      cidr_blocks = "0.0.0.0/0"
    },
  ]

  egress_with_cidr_blocks = [
    {
      rule        = "http-80-tcp"
      cidr_blocks = "0.0.0.0/0"
    },
    {
      rule        = "https-443-tcp"
      cidr_blocks = "0.0.0.0/0"
    },
  ]

  number_of_computed_egress_with_source_security_group_id = 1

  computed_egress_with_source_security_group_id = [
    {
      rule                     = "ssh-tcp"
      source_security_group_id = "${module.sg_ec2_nginx.this_security_group_id}"
    },
  ]
}

module "sg_ec2_nginx" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "2.16.0"

  name        = "ec2-nginx"
  description = "nginx Security Group"
  vpc_id      = "${aws_vpc.vpc.id}"

  egress_with_cidr_blocks = [
    {
      rule        = "http-80-tcp"
      cidr_blocks = "0.0.0.0/0"
    },
    {
      rule        = "https-443-tcp"
      cidr_blocks = "0.0.0.0/0"
    },
  ]

  number_of_computed_ingress_with_source_security_group_id = 3

  computed_ingress_with_source_security_group_id = [
    {
      rule                     = "ssh-tcp"
      source_security_group_id = "${module.sg_ec2_bastion.this_security_group_id}"
    },
    {
      rule                     = "http-80-tcp"
      source_security_group_id = "${module.sg_alb_nginx.this_security_group_id}"
    },
    {
      rule                     = "https-443-tcp"
      source_security_group_id = "${module.sg_alb_nginx.this_security_group_id}"
    },
  ]
}

module "sg_alb_nginx" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "2.16.0"

  name        = "alb-nginx"
  description = "ALB Security Group"
  vpc_id      = "${aws_vpc.vpc.id}"

  ingress_with_cidr_blocks = [
    {
      rule        = "http-80-tcp"
      cidr_blocks = "0.0.0.0/0"
    },
    {
      rule        = "https-443-tcp"
      cidr_blocks = "0.0.0.0/0"
    },
  ]

  number_of_computed_egress_with_source_security_group_id = 2

  computed_egress_with_source_security_group_id = [
    {
      rule                     = "http-80-tcp"
      source_security_group_id = "${module.sg_ec2_nginx.this_security_group_id}"
    },
    {
      rule                     = "https-443-tcp"
      source_security_group_id = "${module.sg_ec2_nginx.this_security_group_id}"
    },
  ]
}

resource "aws_lb" "nginx" {
  load_balancer_type = "application"

  enable_cross_zone_load_balancing = true

  security_groups = [
    "${module.sg_alb_nginx.this_security_group_id}",
  ]

  subnets = [
    "${aws_subnet.subnet-a.id}",
    "${aws_subnet.subnet-b.id}",
    "${aws_subnet.subnet-c.id}",
  ]
}

resource "aws_lb_listener" "nginx_80" {
  load_balancer_arn = "${aws_lb.nginx.arn}"

  port     = 80
  protocol = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = "${aws_lb_target_group.nginx_80.arn}"
  }
}

resource "aws_lb_target_group" "nginx_80" {
  vpc_id   = "${aws_vpc.vpc.id}"
  port     = 80
  protocol = "HTTP"

  health_check {
    interval            = 5
    port                = "traffic-port"
    path                = "/"
    protocol            = "HTTP"
    timeout             = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200-299,300-399,404"
  }
}

resource "aws_lb_target_group_attachment" "nginx_80" {
  count = "${var.instance-count}"

  target_group_arn = "${aws_lb_target_group.nginx_80.arn}"
  target_id        = "${element(aws_instance.instance.*.id, count.index)}"
  port             = 80
}

output "nginx_domain" {
  value = "http://${aws_lb.nginx.dns_name}"
}
