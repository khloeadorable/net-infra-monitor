variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "net-infra-monitor"
}

variable "instance_type" {
  type    = string
  default = "t2.micro"
}

variable "allowed_ssh_cidr" {
  description = "CIDR allowed to SSH into monitored nodes. Set to your IP/32."
  type        = string
}

variable "alert_email" {
  type = string
}
