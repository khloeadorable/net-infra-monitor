# Net-Infra-Monitor

A small infrastructure health dashboard, built to demonstrate a complete,
real (if intentionally small) DevOps loop: modular IaC with remote state,
keyless CI/CD via OIDC, a manual approval gate before any AWS change, real
network health checks (not mock data), structured logging, and an
operational runbook.

It is a portfolio project, not production software for a company with
real users. The "What's intentionally simple" section below is there on
purpose — pretending otherwise would be a worse signal than just saying
it plainly.

## Architecture

```
                    ┌─────────────────────────────┐
                    │   terraform/bootstrap/        │
                    │   (run once, manually)        │
                    │   - S3 state bucket           │
                    │   - DynamoDB lock table        │
                    │   - GitHub OIDC provider + role│
                    └──────────────┬─────────────────┘
                                   │ outputs feed the
                                   │ backend block below
                                   ▼
   PR opened ──▶ lint, test, terraform plan ──▶ plan posted as PR comment
                                   │
                        merge to main
                                   ▼
                    ┌──────────────────────────────┐
   GitHub Actions    │ terraform/environments/dev/   │
   (OIDC, no static ─▶│  - module "node"  (EC2)       │
    AWS keys)         │  - module "alerting" (SNS +   │
                       │    CloudWatch alarm)          │
                       │  - S3 target bucket           │
                       └──────────────┬─────────────────┘
                                      │ MANUAL APPROVAL GATE
                                      │ (GitHub Environment)
                                      ▼
                              terraform apply
                                      │
                                      ▼
                    ┌─────────────────────────────┐
                    │  Real AWS resources           │
                    │  - EC2 + 7-line health server │
                    │  - S3 bucket                  │
                    │  - SNS topic                  │
                    │  - CloudWatch alarm            │
                    └──────────────┬─────────────────┘
                                   │ terraform output -json
                                   ▼
                     scripts/sync_targets.py
                                   ▼
                       config/nodes.json
                                   ▼
            src/app.py (Streamlit) ──▶ real HTTP/TCP checks
                                   │         │
                          structured JSON    └─▶ SNS alert on
                          logs to stdout          threshold breach
```

## What's real here

- **Modular Terraform** (`terraform/modules/`) — `monitored-node` and
  `alerting` are reusable, parameterized modules, not copy-pasted
  resource blocks. `environments/dev` composes them; a `staging` or
  `prod` environment would reuse the same modules with different
  variables.
- **Remote state with locking** — `terraform/bootstrap/` provisions an
  S3 bucket (versioned, encrypted, public access blocked) and a
  DynamoDB lock table. `environments/dev` points its backend at them.
  Bootstrap is deliberately a separate config: you can't point Terraform
  at a backend that doesn't exist yet, so the bucket that *holds* state
  can't itself be created by the config that *uses* that state.
- **Keyless CI/CD via OIDC** (`terraform/bootstrap/github-oidc.tf`) —
  GitHub Actions assumes a scoped IAM role via OpenID Connect. No AWS
  access keys are stored as GitHub secrets, anywhere, ever. The IAM
  policy is scoped to the specific services this project touches, not
  `AdministratorAccess`.
- **A manual approval gate before `apply`** — the `terraform-apply` job
  in CI uses a GitHub Environment (`production-infra`) configured with a
  required reviewer. `terraform plan` runs automatically and is posted
  as a PR comment; nothing actually changes in AWS until a human clicks
  approve.
- **Two independent health signals, on purpose** — `src/checker.py` does
  real `requests.get()` / `socket.create_connection()` calls and
  measures genuine round-trip latency (app-level). A CloudWatch alarm
  watches the EC2 instance's own `StatusCheckFailed` metric
  (infra-level). These catch different failure modes — see
  [`RUNBOOK.md`](RUNBOOK.md) for why that distinction matters in
  practice.
- **Structured logging** (`src/logging_config.py`) — every health check
  emits a JSON log line with the node, target, latency, and reachability
  as queryable fields, not a free-text string.
- **A runbook, not just a README** — [`RUNBOOK.md`](RUNBOOK.md) covers
  what to actually do for each alert type, including how to tell apart
  failure modes that look identical on the dashboard but require
  different fixes, and how to test the alert path itself before trusting
  it in an emergency.
- **Tests that exercise real failure paths** — `tests/` mocks the
  network boundary (so tests don't need live AWS resources or network
  access) but exercises the actual `checker.py` and `alerts.py` logic,
  including timeout, connection-refused, and 5xx response paths.

## What's intentionally simple

- Single environment (`dev`) wired up. The module structure supports
  adding `staging`/`prod` environment directories that reuse the same
  modules — that's *why* it's modular — but only `dev` is actually
  provisioned here, because running multiple paid environments for a
  portfolio project isn't worth it.
- One EC2 instance, not an Auto Scaling Group. At real scale you'd want
  the monitored fleet itself to be dynamic (e.g. discovered via AWS tags
  or a service registry) rather than a fixed list in `config/nodes.json`.
  Doing that properly would mean the monitor discovers targets instead
  of being told about them — a reasonable next step, scoped out here for
  time.
- The EC2 "health server" is a 7-line `http.server` script injected via
  `user_data`, not a real application — it exists to give the checker
  something genuine to probe over the network, not to model a real
  service.
- No auth on the Streamlit dashboard. Fine for a demo behind a private
  Render URL; not fine for anything with real users or sensitive data.
- Alerting is a single SNS email subscription, not a paging/escalation
  system (no PagerDuty/Opsgenie integration, no on-call schedule). SNS
  is the right small-scale building block for that, but is not itself
  an incident management system.
- No Kubernetes. Running a single EC2 instance and a Streamlit container
  doesn't need an orchestrator, and adding one here would be padding,
  not depth.

## Running it locally

```bash
cp .env.example .env          # fill in SNS_TOPIC_ARN if you want alerts
cp config/nodes.json.example config/nodes.json   # or generate via Terraform, see below
docker compose up --build
# dashboard at http://localhost:8501
```

## Provisioning real infrastructure

**One-time setup** (per AWS account):

```bash
cd terraform/bootstrap
terraform init
terraform apply -var="state_bucket_name=your-unique-tfstate-bucket-name"
# Note the state_bucket_name and lock_table_name outputs

# Then, separately, set up GitHub OIDC (same directory):
terraform apply -var="github_org=your-username" -var="github_repo=net-infra-monitor"
# Note the github_actions_role_arn output — set it as the AWS_ROLE_ARN
# secret in your GitHub repo settings.
```

Edit `terraform/environments/dev/provider.tf`'s `backend "s3"` block with
your real bucket/table names (Terraform doesn't allow variable
interpolation in backend blocks — this is a known limitation, not an
oversight).

**Provisioning the monitored infrastructure:**

```bash
cd terraform/environments/dev
cp terraform.tfvars.example terraform.tfvars   # set allowed_ssh_cidr to YOUR_IP/32
terraform init
terraform plan
terraform apply

cd ../../..
python scripts/sync_targets.py    # writes config/nodes.json from real outputs
```

In CI, this flow is automatic: open a PR to see the plan as a comment,
merge to `main` to trigger plan → manual approval → apply → app deploy.

**Cost:** the EC2 instance defaults to `t2.micro`, and S3/DynamoDB usage
here is minimal — this fits within the AWS free tier for a new account.
Outside free tier, it's roughly $0.01/hour for the instance plus
negligible storage costs. Run `terraform destroy` in
`environments/dev` when done; the bootstrap state bucket has
`prevent_destroy` set, so tearing that down requires deliberately
removing that lifecycle block first.

## Running tests

```bash
pip install -r requirements-dev.txt
pytest tests/ -v --cov=src
ruff check src/ tests/
```

## Tech stack

- **App:** Python, Streamlit, `requests`, structured JSON logging
- **Infra:** Terraform (modules, remote state + locking), AWS (EC2, S3,
  SNS, CloudWatch, IAM/OIDC)
- **Containerization:** Docker (multi-stage, non-root user, healthcheck)
- **CI/CD:** GitHub Actions — lint → test → plan (commented on PRs) →
  manual approval → apply → deploy, authenticated via OIDC

## Possible next steps

- Dynamic target discovery (tag-based or service registry) instead of a
  static `config/nodes.json`
- `staging` and `prod` environment directories reusing the existing
  modules, with environment-specific approval requirements
- Replace the email-only SNS subscription with a real paging
  integration for anything beyond a portfolio context
- Prometheus/Grafana (or CloudWatch dashboards directly) instead of
  Streamlit, if this needed to be a long-running production monitor
  rather than a demo

## License

MIT — see [LICENSE](LICENSE).
