# SNS is the notification fan-out: app-level alerts (from src/alerts.py) and
# infrastructure-level alerts (the CloudWatch alarm below) both publish here,
# so there's one place a human subscribes regardless of which layer detected
# the problem.

resource "aws_sns_topic" "alerts" {
  name = "${var.name}-alerts"
  tags = var.tags
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Infrastructure-level alarm: catches the case the app-level checker can't —
# the instance itself failing AWS's own status checks (host or system issue),
# independent of whether our HTTP health endpoint happens to still respond.
resource "aws_cloudwatch_metric_alarm" "instance_status_check" {
  alarm_name          = "${var.name}-instance-status-check-failed"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods   = 2
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "Triggers when the underlying EC2 instance fails AWS status checks (distinct from our own app-level HTTP check)."
  treat_missing_data  = "breaching"

  dimensions = {
    InstanceId = var.instance_id
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = var.tags
}
