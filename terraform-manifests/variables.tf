# Input Variables
# AWS Region
variable "aws_region" {
  description = "Region in which AWS Resources to be created"
  type        = string
}

variable "s3_bucket" {
  description = "S3 Bucket for storing artifacts & tfstate"
  type        = string
}

variable "resource_name" {
  description = "Naming convention for the AWS Resources to be created"
  type        = string
}

variable "environment" {
  description = "Naming convention for the AWS Resources to be created"
  type        = string
}

variable "instance_type" {
  description = "EC2 Instance Type"
  type        = string
  default     = "t3.nano"
}

variable "volume_size" {
  description = "EC2 Volume Size (in GBs)"
  type        = number
  default     = 10
}

variable "connect_to_instance" {
  description = "Configure the necessary Security Group rules to connect to the created ec2 instance"
  type        = bool
  default     = true
}

variable "create_syncthing_config" {
  description = "Create a new syncthing instance configuration, if set to false the configuration will be take from AWS SSM and S3. See README.md for more info"
  type        = bool
  default     = false
}

variable "connect_to_tailscale" {
  description = "Run the necessary commands in the EC2 Instance to connect to the Tailscale Network. See README.md for more info"
  type        = bool
  default     = true
}

