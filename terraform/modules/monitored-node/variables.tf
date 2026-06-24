variable "name" {
  description = "Name for this monitored node, used in resource naming/tags"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type. Default stays within AWS free tier."
  type        = string
  default     = "t2.micro"
}

variable "allowed_ssh_cidr" {
  description = "CIDR allowed to SSH into the node. Never default this to 0.0.0.0/0."
  type        = string
}

variable "vpc_id" {
  description = "VPC to launch the node in"
  type        = string
}

variable "subnet_id" {
  description = "Subnet to launch the node in"
  type        = string
}

variable "tags" {
  description = "Additional tags to merge onto all resources in this module"
  type        = map(string)
  default     = {}
}
