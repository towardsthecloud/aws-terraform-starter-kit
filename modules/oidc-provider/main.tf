# GitHub Actions OIDC Provider Module
# This module creates an OIDC provider and IAM role for GitHub Actions

# Data source to find existing OIDC provider
data "aws_iam_openid_connect_provider" "github_actions" {
  count = var.use_existing_oidc_provider ? 1 : 0
  url   = "https://token.actions.githubusercontent.com"
}

# Create the OIDC provider for GitHub Actions (only if not using existing)
resource "aws_iam_openid_connect_provider" "github_actions" {
  count = var.use_existing_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"

  client_id_list = var.audience_list

  thumbprint_list = [var.github_thumbprint]

  tags = merge(
    {
      Name        = "GitHubActionsOIDCProvider"
      Description = "OIDC provider for GitHub Actions"
      Repository  = var.github_repo
    },
    var.tags
  )
}

# Local value to reference the OIDC provider ARN
locals {
  oidc_provider_arn = var.use_existing_oidc_provider ? data.aws_iam_openid_connect_provider.github_actions[0].arn : aws_iam_openid_connect_provider.github_actions[0].arn
}

# Data source to construct the subject claim for the trust policy
locals {
  # Subject claim format: repo:OWNER/REPO:ref:refs/heads/BRANCH
  # Using wildcard to allow all branches and environments
  github_subject_claim = "repo:${var.github_repo}:*"
}

# IAM role for GitHub Actions
resource "aws_iam_role" "github_actions" {
  name        = var.role_name
  path        = var.path
  description = "IAM role for GitHub Actions OIDC authentication"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = local.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringLike = {
            "token.actions.githubusercontent.com:sub" = local.github_subject_claim
          }
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  max_session_duration = var.max_session_duration

  tags = merge(
    {
      Name        = var.role_name
      Description = "GitHub Actions service role"
      Repository  = var.github_repo
    },
    var.tags
  )
}

# Attach managed policies to the role
resource "aws_iam_role_policy_attachment" "github_actions" {
  for_each = toset(var.managed_policy_arns)

  role       = aws_iam_role.github_actions.name
  policy_arn = each.value
}

# Optional: Attach custom inline policies
resource "aws_iam_role_policy" "github_actions_inline" {
  for_each = var.inline_policies

  name   = each.key
  role   = aws_iam_role.github_actions.id
  policy = each.value
}
