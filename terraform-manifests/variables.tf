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

