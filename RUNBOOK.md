# Runbook

Operational procedures for Net-Infra-Monitor. Written for whoever's on
call — including future-me at 2am — not as documentation theater.

## Alert: Node unreachable (EC2 health check failing)

**Signal:** Dashboard shows `Warning` status with `Reachable: False` for
`EC2-Health-Node`, or the `${project}-dev-instance-status-check-failed`
CloudWatch alarm has fired.

**Two distinct failure modes, check in this order:**

1. **App-level only** (CloudWatch alarm is OK, dashboard shows Warning):
   the HTTP health server on the instance has likely died, but the
   instance itself is healthy. SSH in and check:
   ```
   ssh ec2-user@<node_public_ip>
   ps aux | grep health_server
   cat /var/log/health_server.log
   ```
   Fix: `nohup python3 /home/ec2-user/health_server.py > /var/log/health_server.log 2>&1 &`

2. **Infra-level** (CloudWatch alarm has also fired): the underlying EC2
   instance failed AWS's own status checks. This is not something the
   app can fix. Check the AWS console → EC2 → Instances → Status Checks
   tab for which check failed (system vs. instance). A system-level
   failure usually means an AWS-side hardware/hypervisor issue — stop
   and start the instance (not reboot; stop/start moves it to new
   hardware). An instance-level failure usually means something inside
   the OS — check `/var/log/messages` via the EC2 serial console if SSH
   is unresponsive.

**Why these are separate alarms:** an HTTP 200 from our own health
server tells you the app thinks it's fine. It says nothing about the
instance underneath it failing AWS's own checks. Relying on app-level
checks alone would mean missing infra-level failures where the OS is
wedged but our long-running Python process is still technically running.

## Alert: Latency threshold breach

**Signal:** Dashboard shows `Warning` with high `Latency (ms)` but
`Reachable: True`.

This is *not* paged automatically by CloudWatch (only reachability is) —
it's surfaced via SNS only if "Send SNS alerts on breach" is enabled in
the dashboard sidebar, since latency thresholds are subjective and
environment-dependent.

1. Check whether this is one node or all nodes — if all, it's likely a
   network path issue from wherever the dashboard is running (e.g. the
   Render instance), not the targets themselves.
2. If one node, check that instance's CPU via CloudWatch — `t2.micro`
   instances are burstable and will throttle hard once CPU credits are
   exhausted, which shows up as latency, not unavailability.
3. No immediate action required for a single transient breach — the
   dashboard re-checks on a `ttl=10` cache, so confirm it's persistent
   before treating it as real.

## Alert: SNS email never arrived

1. Check the subscription is actually confirmed: AWS console → SNS →
   Subscriptions. A new `alert_email` in tfvars creates a
   *pending* subscription — AWS sends a confirmation link that must be
   clicked once before the subscription delivers anything. This is the
   most common reason alerts "don't work" right after first apply.
2. Check spam folder — AWS SNS confirmation/notification emails get
   filtered surprisingly often.

## Runbook for the runbook: testing this actually works

Don't trust an alert path you haven't fired in anger. To test end to end:

```bash
# Manually publish a test alert through the real SNS topic
aws sns publish \
  --topic-arn "$(cd terraform/environments/dev && terraform output -raw sns_topic_arn)" \
  --subject "Test alert" \
  --message "This is a manual test of the alert path, not a real incident."
```

If the email doesn't arrive within a minute or two, the problem is in
SNS/subscription config, not the application — that isolates the
failure domain immediately.

## Terraform state lock stuck

If a CI run dies mid-apply, the DynamoDB lock can be left held. Symptom:
`Error acquiring the state lock`. Check who holds it and, only after
confirming no other apply is actually in progress:

```bash
cd terraform/environments/dev
terraform force-unlock <lock-id-from-error-message>
```

Don't force-unlock reflexively — confirm in the GitHub Actions tab that
no `terraform-apply` job is actually mid-run first.
