# Terraform Block
terraform {
  required_version = "~> 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }

  backend "s3" {
    bucket = "<this will be changed after terraform init>"
    key    = "<this will be changed after terraform init>"
    region = "<this will be changed after terraform init>"
  }
}

# Provider Block
provider "aws" {
  region  = var.aws_region
  profile = "default"
  default_tags {
    tags = {
      environment   = var.environment
      resource_name = var.resource_name
      region        = var.aws_region
    }
  }
}
