# Bootstrap: creates the S3 bucket + DynamoDB lock table that the main
# environments/ configs use as their remote backend.
#
# This has to be a SEPARATE Terraform config with its own (local) state,
# because you can't configure a backend that doesn't exist yet — chicken
# and egg. Run this once, by hand, before anything in environments/.
#
#   cd terraform/bootstrap
#   terraform init
#   terraform apply
#
# After this exists, environments/dev can point its backend at the bucket
# it creates. You will not need to run this again unless you tear down
# the state backend itself (don't do that casually).

terraform {
  required_version = ">= 1.7.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "state_bucket_name" {
  description = "Globally-unique name for the Terraform state bucket"
  type        = string
}

provider "aws" {
  region = var.aws_region
}

resource "aws_s3_bucket" "tfstate" {
  bucket = var.state_bucket_name

  # Prevents `terraform destroy` from silently deleting your state history.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "tf_lock" {
  name         = "${var.state_bucket_name}-lock"
  billing_mode = "PAY_PER_REQUEST" # free-tier friendly, no provisioned capacity to manage
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

output "state_bucket_name" {
  value = aws_s3_bucket.tfstate.bucket
}

output "lock_table_name" {
  value = aws_dynamodb_table.tf_lock.name
}
