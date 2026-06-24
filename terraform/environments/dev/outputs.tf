output "node_health_url" {
  value = module.node.health_url
}

output "s3_bucket_name" {
  value = aws_s3_bucket.monitor_target.bucket
}

output "sns_topic_arn" {
  value = module.alerting.topic_arn
}
