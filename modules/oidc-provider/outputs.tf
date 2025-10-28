# Outputs for GitHub Actions OIDC Provider Module

output "oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider"
  value       = local.oidc_provider_arn
}

output "oidc_provider_url" {
  description = "URL of the GitHub Actions OIDC provider"
  value       = "https://token.actions.githubusercontent.com"
}

output "role_arn" {
  description = "ARN of the GitHub Actions IAM role"
  value       = aws_iam_role.github_actions.arn
}

output "role_name" {
  description = "Name of the GitHub Actions IAM role"
  value       = aws_iam_role.github_actions.name
}

output "role_id" {
  description = "ID of the GitHub Actions IAM role"
  value       = aws_iam_role.github_actions.id
}

output "role_unique_id" {
  description = "Unique ID of the GitHub Actions IAM role"
  value       = aws_iam_role.github_actions.unique_id
}
