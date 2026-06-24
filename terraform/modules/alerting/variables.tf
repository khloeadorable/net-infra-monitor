variable "name" {
  description = "Name prefix for alerting resources"
  type        = string
}

variable "alert_email" {
  description = "Email address subscribed to the SNS topic"
  type        = string
}

variable "instance_id" {
  description = "EC2 instance ID to attach a status-check alarm to"
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
