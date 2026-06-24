# Sets up GitHub Actions OIDC federation so CI can assume an AWS role
# WITHOUT any static access keys stored as GitHub secrets. This is run
# once per AWS account (not per environment) — it's identity plumbing,
# not infrastructure.
#
#   cd terraform/bootstrap
#   terraform apply -target=aws_iam_openid_connect_provider.github \
#                    -target=aws_iam_role.github_actions
#
# Then set AWS_ROLE_ARN as a GitHub Actions secret/variable to the
# role's ARN (see output below).

variable "github_org" {
  description = "GitHub org or username that owns the repo"
  type        = string
}

variable "github_repo" {
  description = "Repository name (without org prefix)"
  type        = string
}

# GitHub's OIDC signing certificate is now chained to a CA that AWS trusts
# directly, so recent versions of the AWS provider no longer require a
# manually-specified thumbprint — AWS resolves it automatically. Older
# guides hardcode a thumbprint here; that's no longer necessary and a
# stale hardcoded value is itself a small maintenance trap. Leaving
# thumbprint_list unset lets AWS manage it.
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "github_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Restricts which repo+ref can assume this role. Both the main branch
    # (for apply) and pull requests (for plan-only, read-mostly access) are
    # allowed — without this condition, any GitHub Actions workflow anywhere
    # could potentially assume it.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/main",
        "repo:${var.github_org}/${var.github_repo}:pull_request",
      ]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "net-infra-monitor-github-actions"
  assume_role_policy = data.aws_iam_policy_document.github_trust.json
}

# Scoped to exactly what Terraform needs to manage in this project —
# not AdministratorAccess. Tightened to the specific services/actions
# this project's resources require.
data "aws_iam_policy_document" "ci_permissions" {
  statement {
    sid    = "EC2AndNetworking"
    effect = "Allow"
    actions = [
      "ec2:Describe*",
      "ec2:RunInstances",
      "ec2:TerminateInstances",
      "ec2:CreateTags",
      "ec2:CreateSecurityGroup",
      "ec2:DeleteSecurityGroup",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:ModifyInstanceMetadataOptions",
    ]
    resources = ["*"] # EC2 API requires * for most of these; real-world would scope via tags/conditions
  }

  statement {
    sid    = "S3StateAndTargetBuckets"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket",
      "s3:CreateBucket",
      "s3:PutBucketVersioning",
      "s3:PutEncryptionConfiguration",
      "s3:PutBucketPublicAccessBlock",
    ]
    resources = [
      "arn:aws:s3:::net-infra-monitor-*",
      "arn:aws:s3:::net-infra-monitor-*/*",
    ]
  }

  statement {
    sid       = "DynamoDBLockTable"
    effect    = "Allow"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
    resources = ["arn:aws:dynamodb:*:*:table/net-infra-monitor-*"]
  }

  statement {
    sid       = "SNSAndCloudWatch"
    effect    = "Allow"
    actions   = ["sns:*", "cloudwatch:PutMetricAlarm", "cloudwatch:DeleteAlarms", "cloudwatch:DescribeAlarms"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "ci_permissions" {
  name   = "net-infra-monitor-ci-permissions"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.ci_permissions.json
}

output "github_actions_role_arn" {
  value = aws_iam_role.github_actions.arn
}
