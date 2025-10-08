# Advanced Usage Guide

This document provides advanced usage patterns and best practices for the AWS Terraform Starter Kit.

## Environment-Specific Deployments

### Using Environment Files

The `environments/` directory contains pre-configured variable files for different environments:

```bash
# Deploy to development
terraform plan -var-file="environments/dev.tfvars"
terraform apply -var-file="environments/dev.tfvars"

# Deploy to staging
terraform plan -var-file="environments/staging.tfvars"
terraform apply -var-file="environments/staging.tfvars"

# Deploy to production
terraform plan -var-file="environments/prod.tfvars"
terraform apply -var-file="environments/prod.tfvars"
```

### Workspace Management

Use Terraform workspaces for environment isolation:

```bash
# Create and switch to development workspace
terraform workspace new dev
terraform workspace select dev

# Create and switch to production workspace
terraform workspace new prod
terraform workspace select prod

# List workspaces
terraform workspace list

# Show current workspace
terraform workspace show
```

## Remote State Backend Setup

### Initial State Backend Creation

1. First deployment (local state):
```bash
terraform init
terraform apply
```

2. Note the state bucket and DynamoDB table from outputs:
```bash
terraform output terraform_state_bucket
terraform output terraform_state_lock_table
```

3. Update `terraform.tf` with the backend configuration:
```hcl
backend "s3" {
  bucket         = "your-project-terraform-state-xxxxx"
  key            = "terraform/state.tfstate"
  region         = "us-east-1"
  dynamodb_table = "your-project-terraform-state-lock"
  encrypt        = true
}
```

4. Migrate to remote state:
```bash
terraform init -migrate-state
```

### Environment-Specific State Keys

For multiple environments, use different state keys:

```hcl
# Development
backend "s3" {
  bucket = "your-project-terraform-state-xxxxx"
  key    = "environments/dev/terraform.tfstate"
  # ... other config
}

# Production
backend "s3" {
  bucket = "your-project-terraform-state-xxxxx"
  key    = "environments/prod/terraform.tfstate"
  # ... other config
}
```

## Advanced Terraform Commands

### Planning with Output

```bash
# Save plan to file
terraform plan -out=tfplan

# Apply saved plan
terraform apply tfplan

# Show plan in JSON format
terraform show -json tfplan
```

### Targeting Specific Resources

```bash
# Plan only specific resource
terraform plan -target=aws_s3_bucket.demo_bucket

# Apply only specific resource
terraform apply -target=aws_s3_bucket.demo_bucket
```

### Import Existing Resources

```bash
# Import existing S3 bucket
terraform import aws_s3_bucket.demo_bucket existing-bucket-name

# Import existing DynamoDB table
terraform import aws_dynamodb_table.terraform_state_lock existing-table-name
```

## CI/CD Advanced Patterns

### Environment-Specific Workflows

Create separate workflow files for each environment:

```yaml
# .github/workflows/terraform-dev.yml
name: Terraform Dev
on:
  push:
    branches: [ develop ]
env:
  TF_VAR_FILE: environments/dev.tfvars
```

### Matrix Builds

Deploy to multiple environments in parallel:

```yaml
strategy:
  matrix:
    environment: [dev, staging, prod]
steps:
  - name: Terraform Apply
    run: terraform apply -var-file="environments/${{ matrix.environment }}.tfvars"
```

### Conditional Deployments

```yaml
- name: Deploy to Production
  if: github.ref == 'refs/heads/main'
  run: terraform apply -var-file="environments/prod.tfvars"
```

## Security Best Practices

### IAM Policies

Create least-privilege IAM policies for Terraform:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:*",
        "dynamodb:*",
        "iam:GetRole",
        "iam:PassRole"
      ],
      "Resource": "*"
    }
  ]
}
```

### Secrets Management

Use AWS Secrets Manager or Parameter Store for sensitive values:

```hcl
data "aws_secretsmanager_secret_version" "db_password" {
  secret_id = "myapp/database/password"
}

resource "aws_db_instance" "example" {
  password = data.aws_secretsmanager_secret_version.db_password.secret_string
}
```

### State Encryption

Ensure state files are encrypted:

```hcl
resource "aws_s3_bucket_server_side_encryption_configuration" "state_encryption" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.terraform_state.arn
    }
  }
}
```

## Monitoring and Alerting

### CloudTrail Integration

Enable CloudTrail for Terraform operations:

```hcl
resource "aws_cloudtrail" "terraform_trail" {
  name           = "${var.project_name}-terraform-trail"
  s3_bucket_name = aws_s3_bucket.cloudtrail_bucket.bucket

  event_selector {
    read_write_type                 = "All"
    include_management_events       = true
    data_resource {
      type   = "AWS::S3::Object"
      values = ["${aws_s3_bucket.terraform_state.arn}/*"]
    }
  }
}
```

### Cost Monitoring

Add cost allocation tags:

```hcl
default_tags {
  tags = {
    Environment    = var.environment
    Project        = var.project_name
    CostCenter     = var.cost_center
    Owner          = var.owner
    ManagedBy      = "terraform"
    CreatedDate    = formatdate("YYYY-MM-DD", timestamp())
  }
}
```

## Troubleshooting

### Common Issues

1. **State Lock Conflicts**:
```bash
# Force unlock (use carefully)
terraform force-unlock LOCK_ID
```

2. **Provider Version Conflicts**:
```bash
# Upgrade providers
terraform init -upgrade
```

3. **State Corruption**:
```bash
# Pull remote state
terraform state pull > backup.tfstate

# Restore from backup
terraform state push backup.tfstate
```

### Debug Mode

Enable detailed logging:

```bash
export TF_LOG=DEBUG
export TF_LOG_PATH=./terraform.log
terraform apply
```

## Performance Optimization

### Parallel Execution

```bash
# Increase parallelism
terraform apply -parallelism=20
```

### Provider Optimization

```hcl
provider "aws" {
  region = var.aws_region
  
  # Skip unnecessary API calls
  skip_get_ec2_platforms      = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
  skip_credentials_validation = true
}
```

## Module Development

### Creating Reusable Modules

```hcl
# modules/s3-bucket/main.tf
resource "aws_s3_bucket" "this" {
  bucket = var.bucket_name
  tags   = var.tags
}

# modules/s3-bucket/variables.tf
variable "bucket_name" {
  description = "Name of the S3 bucket"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

# modules/s3-bucket/outputs.tf
output "bucket_id" {
  description = "ID of the S3 bucket"
  value       = aws_s3_bucket.this.id
}
```

### Using Local Modules

```hcl
module "demo_bucket" {
  source = "./modules/s3-bucket"
  
  bucket_name = local.bucket_name
  tags        = local.common_tags
}
```

## Testing

### Terraform Testing Framework

```hcl
# tests/main.tftest.hcl
run "valid_bucket_name" {
  command = plan

  assert {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", aws_s3_bucket.demo_bucket.bucket))
    error_message = "Bucket name must be valid DNS name"
  }
}
```

### Integration Testing

Use tools like Terratest:

```go
func TestTerraformS3Example(t *testing.T) {
    terraformOptions := &terraform.Options{
        TerraformDir: "../",
        VarFiles:     []string{"environments/dev.tfvars"},
    }

    defer terraform.Destroy(t, terraformOptions)
    terraform.InitAndApply(t, terraformOptions)

    bucketName := terraform.Output(t, terraformOptions, "bucket_name")
    assert.NotEmpty(t, bucketName)
}
```

## Migration Strategies

### From Other IaC Tools

#### From CloudFormation
1. Use `former2` to export CloudFormation to Terraform
2. Import existing resources
3. Gradually migrate resources

#### From AWS CDK
1. Use `cdktf` for gradual migration
2. Convert CDK constructs to Terraform modules
3. Import state from CDK deployments

### Version Upgrades

```bash
# Check for required changes
terraform init -upgrade
terraform plan

# Use terraform 0.13upgrade for major version bumps
terraform 0.13upgrade
```

## Advanced Patterns

### Conditional Resources

```hcl
resource "aws_cloudwatch_log_group" "app_logs" {
  count = var.enable_logging ? 1 : 0
  name  = "/aws/lambda/${var.function_name}"
}
```

### Dynamic Blocks

```hcl
resource "aws_security_group" "example" {
  name = "example"

  dynamic "ingress" {
    for_each = var.ingress_rules
    content {
      from_port   = ingress.value.from_port
      to_port     = ingress.value.to_port
      protocol    = ingress.value.protocol
      cidr_blocks = ingress.value.cidr_blocks
    }
  }
}
```

### For Expressions

```hcl
locals {
  bucket_objects = {
    for idx, obj in var.objects : obj.key => obj
  }
}
```

This guide provides advanced patterns for scaling your Terraform infrastructure. Adapt these patterns based on your specific requirements and organizational policies.