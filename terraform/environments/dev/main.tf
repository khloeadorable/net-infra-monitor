data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_caller_identity" "current" {}

module "node" {
  source = "../../modules/monitored-node"

  name             = "${var.project_name}-dev-node-01"
  instance_type    = var.instance_type
  allowed_ssh_cidr = var.allowed_ssh_cidr
  vpc_id           = data.aws_vpc.default.id
  subnet_id        = data.aws_subnets.default.ids[0]

  tags = {
    Environment = "dev"
  }
}

module "alerting" {
  source = "../../modules/alerting"

  name        = "${var.project_name}-dev"
  alert_email = var.alert_email
  instance_id = module.node.instance_id

  tags = {
    Environment = "dev"
  }
}

resource "aws_s3_bucket" "monitor_target" {
  bucket = "${var.project_name}-dev-target-${data.aws_caller_identity.current.account_id}"
  tags = {
    Environment = "dev"
  }
}

resource "aws_s3_bucket_public_access_block" "monitor_target" {
  bucket                  = aws_s3_bucket.monitor_target.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
