resource "aws_instance" "syncthing" {
  depends_on = [
    aws_cloudwatch_log_group.ec2_log_group,
    aws_ssm_document.cloud_init_wait,
    aws_ssm_document.tailscale_logout
  ]

  ami           = data.aws_ami.amzlinux2.id
  instance_type = var.instance_type

  user_data = file("${path.module}/../scripts/user-data.sh")

  iam_instance_profile = aws_iam_instance_profile.ec2_instance_profile.name

  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
    volume_size = var.volume_size
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]

    command = <<-EOF
    set -Ee -o pipefail
    export AWS_DEFAULT_REGION=${var.aws_region}
    sleep 10
    command_id=$(aws ssm send-command --document-name ${aws_ssm_document.cloud_init_wait.arn} --instance-ids ${self.id} --output text --query "Command.CommandId")
    if ! aws ssm wait command-executed --command-id $command_id --instance-id ${self.id}; then
      echo "Failed to start services on instance ${self.id}!";
      echo "stdout:";
      aws ssm get-command-invocation --command-id $command_id --instance-id ${self.id} --query StandardOutputContent;
      echo "stderr:";
      aws ssm get-command-invocation --command-id $command_id --instance-id ${self.id} --query StandardErrorContent;
      exit 1;
    fi;
    echo "Services started successfully on the new instance with id ${self.id}!"

    EOF
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    when        = destroy
    command     = <<-EOF
    set -Ee -o pipefail
    if [ ${self.tags_all["connect_to_tailscale"]} = "false" ]; then
      echo "Nothing to do"
    else
      export AWS_DEFAULT_REGION=${self.tags_all["region"]}
      command_id=$(aws ssm send-command --document-name ${self.tags_all["resource_name"]}-${self.tags_all["environment"]}-tailscale-logout --instance-ids ${self.id} --output text --query "Command.CommandId")    
      if ! aws ssm wait command-executed --command-id $command_id --instance-id ${self.id}; then
        echo "Failed to logout from tailscale on instance ${self.id}!";
        echo "stdout:";
        aws ssm get-command-invocation --command-id $command_id --instance-id ${self.id} --query StandardOutputContent;
        echo "stderr:";
        aws ssm get-command-invocation --command-id $command_id --instance-id ${self.id} --query StandardErrorContent;
        exit 1;
      fi;
      echo "Tailscale logout run succesfully on instance with id ${self.id}!"
    fi
    EOF
  }

  tags = {
    Name                    = "${var.resource_name}-${var.environment}-ec2"
    create_syncthing_config = var.create_syncthing_config
    connect_to_tailscale    = var.connect_to_tailscale
  }
}

resource "aws_cloudwatch_log_group" "ec2_log_group" {
  name              = "/aws/ec2/${var.resource_name}/${var.environment}"
  retention_in_days = 3
}

resource "aws_ssm_document" "cloud_init_wait" {
  name            = "${var.resource_name}-${var.environment}-cloud-init-wait"
  document_type   = "Command"
  document_format = "YAML"
  content         = <<-DOC
    schemaVersion: '2.2'
    description: Wait for cloud init to finish
    mainSteps:
    - action: aws:runShellScript
      name: StopOnLinux
      precondition:
        StringEquals:
        - platformType
        - Linux
      inputs:
        runCommand:
        - cloud-init status --wait
    DOC
}

resource "aws_ssm_document" "tailscale_logout" {
  name            = "${var.resource_name}-${var.environment}-tailscale-logout"
  document_type   = "Command"
  document_format = "YAML"
  content         = <<-DOC
    schemaVersion: '2.2'
    description: Wait for cloud init to finish
    mainSteps:
    - action: aws:runShellScript
      name: StopOnLinux
      precondition:
        StringEquals:
        - platformType
        - Linux
      inputs:
        runCommand:
        - tailscale logout
    DOC
}

resource "aws_iam_role" "ec2_iam_role" {
  name = "${var.resource_name}-${var.environment}-iam-role"
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
          Resource = "arn:aws:s3:::${var.s3_bucket}/artifacts/${var.environment}/*"
        },
        {
          Action   = ["ec2:DescribeInstances"]
          Effect   = "Allow"
          Resource = "*"
        },
        {
          Action   = ["ssm:PutParameter", "ssm:GetParameter"]
          Effect   = "Allow"
          Resource = "arn:aws:ssm:*:*:parameter/${var.resource_name}/${var.environment}/*"
        },
        {
          Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
          Effect   = "Allow"
          Resource = "arn:aws:logs:*:*:log-group:/aws/ec2/${var.resource_name}/${var.environment}:*"
        },
      ]
    })
  }
}

resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "${var.resource_name}-${var.environment}-iam-instance-profile"
  role = aws_iam_role.ec2_iam_role.name
}

# AWS EC2 Instance Terraform Outputs
output "ec2_instance_id" {
  description = "List of IDs of instances"
  value       = aws_instance.syncthing.id
}

output "ec2_public_ip" {
  description = "List of public IP addresses assigned to the instances"
  value       = aws_instance.syncthing.public_ip
}
