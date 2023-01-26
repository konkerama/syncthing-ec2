module "ec2" {
  source        = "terraform-aws-modules/ec2-instance/aws"
  version       = "3.1.0"
  name          = "${var.resource_name}-ec2"
  ami           = data.aws_ami.amzlinux2.id
  instance_type = var.instance_type

  user_data = file("${path.module}/../scripts/user-data.sh")

  iam_instance_profile = aws_iam_instance_profile.ec2_instance_profile.name

  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

  root_block_device = [
    {
      encrypted   = true
      volume_type = "gp3"
      volume_size = var.volume_size
    }
  ]
}

resource "aws_iam_role" "ec2_iam_role" {
  name = "${var.resource_name}-iam-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })

  managed_policy_arns = ["arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"]

  inline_policy {
    name = "my_inline_policy"

    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Action   = ["s3:GetObject"]
          Effect   = "Allow"
          Resource = "arn:aws:s3:::${var.s3_bucket}/artifacts/*"
        },
        {
          Action   = ["ssm:*", "ec2:*"]
          Effect   = "Allow"
          Resource = "*"
        },
      ]
    })
  }
}

resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "${var.resource_name}-iam-instance-profile"
  role = aws_iam_role.ec2_iam_role.name
}

# # AWS EC2 Instance Terraform Outputs
# output "ec2_instance_id" {
#   description = "List of IDs of instances"
#   value       = module.ec2.id
# }

# output "ec2_public_ip" {
#   description = "List of public IP addresses assigned to the instances"
#   value       = module.ec2.public_ip
# }
