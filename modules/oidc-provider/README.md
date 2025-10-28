# GitHub Actions OIDC Provider Module

This Terraform module creates an AWS IAM OIDC provider and role for GitHub Actions authentication, enabling secure, keyless deployments from GitHub Actions workflows.

## Features

- Creates GitHub Actions OIDC provider in AWS
- Creates IAM role with trust policy for GitHub Actions
- Supports managed and inline IAM policies
- Configurable session duration
- Repository-scoped authentication

## Usage

```hcl
module "oidc_provider" {
  source = "../../modules/oidc-provider"

  github_repo         = "myorg/myrepo"
  role_name           = "GitHubActionsServiceRole-Terraform"
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/ReadOnlyAccess"
  ]

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}
```

## Using in GitHub Actions

After creating the OIDC provider and role, use it in your GitHub Actions workflow:

```yaml
- name: Configure AWS credentials
  uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: arn:aws:iam::123456789012:role/GitHubActionsServiceRole-Terraform
    aws-region: us-east-1
```

## Requirements

| Name      | Version  |
| --------- | -------- |
| terraform | >= 1.5.0 |
| aws       | >= 5.0   |

## Inputs

| Name                 | Description                                 | Type           | Default                                      | Required |
| -------------------- | ------------------------------------------- | -------------- | -------------------------------------------- | :------: |
| github_repo          | GitHub repository name (format: owner/repo) | `string`       | n/a                                          |   yes    |
| github_thumbprint    | GitHub OIDC thumbprint                      | `string`       | `"6938fd4d98bab03faadb97b34396831e3780aea1"` |    no    |
| audience_list        | List of allowed audiences                   | `list(string)` | `["sts.amazonaws.com"]`                      |    no    |
| role_name            | Name of the IAM role                        | `string`       | `"GitHubActionsServiceRole-Terraform"`       |    no    |
| path                 | IAM path for the role                       | `string`       | `"/"`                                        |    no    |
| managed_policy_arns  | List of IAM policy ARNs to attach           | `list(string)` | `[]`                                         |    no    |
| inline_policies      | Map of inline policies                      | `map(string)`  | `{}`                                         |    no    |
| max_session_duration | Maximum session duration (seconds)          | `number`       | `3600`                                       |    no    |
| tags                 | Additional resource tags                    | `map(string)`  | `{}`                                         |    no    |

## Outputs

| Name              | Description               |
| ----------------- | ------------------------- |
| oidc_provider_arn | ARN of the OIDC provider  |
| oidc_provider_url | URL of the OIDC provider  |
| role_arn          | ARN of the IAM role       |
| role_name         | Name of the IAM role      |
| role_id           | ID of the IAM role        |
| role_unique_id    | Unique ID of the IAM role |

## Security Considerations

1. **Least Privilege**: Attach only the minimum required IAM policies to the role
2. **Repository Scope**: The trust policy is scoped to your specific repository
3. **Branch Protection**: Consider limiting access to specific branches using subject claims
4. **Session Duration**: Keep session duration as short as practical for your use case

## Example: Custom Inline Policy

```hcl
module "oidc_provider" {
  source = "../../modules/oidc-provider"

  github_repo = "myorg/myrepo"
  role_name   = "GitHubActionsServiceRole-Terraform"

  inline_policies = {
    "S3Access" = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "s3:GetObject",
            "s3:PutObject"
          ]
          Resource = "arn:aws:s3:::my-bucket/*"
        }
      ]
    })
  }
}
```

## References

- [GitHub Actions OIDC Documentation](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [AWS IAM OIDC Identity Providers](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html)
