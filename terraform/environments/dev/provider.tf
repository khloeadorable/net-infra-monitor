terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Fill in bucket/dynamodb_table with the outputs from terraform/bootstrap
  # after you've applied that once. Terraform won't interpolate variables
  # into a backend block, so these are literal strings you edit by hand —
  # that's a real, known Terraform limitation, not an oversight here.
  backend "s3" {
    bucket         = "CHANGE-ME-tfstate-bucket"
    key            = "net-infra-monitor/dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "CHANGE-ME-tfstate-bucket-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = "dev"
      ManagedBy   = "terraform"
    }
  }
}
