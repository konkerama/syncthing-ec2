resource "aws_security_group" "ec2_sg" {
  name        = "${var.resource_name}-${var.environment}-sg"
  description = "Security Group for ${var.resource_name}"
  vpc_id      = data.aws_vpc.vpc.id
}

resource "aws_security_group_rule" "example" {
  count = var.connect_to_instance ? 1 : 0

  type              = "ingress"
  from_port         = 8384
  to_port           = 8384
  protocol          = "tcp"
  description       = "syncthing-gui"
  cidr_blocks       = ["${chomp(data.http.myip.body)}/32"]
  security_group_id = aws_security_group.ec2_sg.id
}

resource "aws_security_group_rule" "allow_all" {
  type              = "egress"
  to_port           = 0
  protocol          = "-1"
  from_port         = 0
  cidr_blocks       = ["0.0.0.0/0"]
  ipv6_cidr_blocks  = ["::/0"]
  security_group_id = aws_security_group.ec2_sg.id
}

