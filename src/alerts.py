"""
Threshold evaluation and alerting.

check_threshold() is pure and unit-testable. publish_alert() does the
real I/O (SNS) and is kept separate so tests never need network access
or AWS credentials.
"""
import logging
import os

logger = logging.getLogger(__name__)


def check_threshold(latency_ms: float | None, threshold_ms: float, reachable: bool = True) -> bool:
    """
    Returns True if this result should be flagged as a Warning.

    A target is in Warning state if it's unreachable, or if its latency
    exceeds the configured threshold.
    """
    if not reachable or latency_ms is None:
        return True
    return latency_ms > threshold_ms


def publish_alert(message: str, topic_arn: str | None = None) -> bool:
    """
    Publishes an alert to the configured SNS topic.

    Returns False (and logs) instead of raising if SNS isn't configured —
    the dashboard should keep working even without alerting wired up.
    """
    topic_arn = topic_arn or os.environ.get("SNS_TOPIC_ARN")
    if not topic_arn:
        logger.warning("SNS_TOPIC_ARN not set; skipping alert: %s", message)
        return False

    try:
        import boto3

        client = boto3.client("sns")
        client.publish(TopicArn=topic_arn, Message=message, Subject="Net-Infra-Monitor Alert")
        return True
    except Exception as e:
        logger.error("Failed to publish alert: %s", e)
        return False
