output "bucket_name" {
  description = "Name of the created S3 bucket"
  value       = aws_s3_bucket.demo_bucket.id
}

output "bucket_arn" {
  description = "ARN of the created S3 bucket"
  value       = aws_s3_bucket.demo_bucket.arn
}

output "bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.demo_bucket.bucket_domain_name
}

output "bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket"
  value       = aws_s3_bucket.demo_bucket.bucket_regional_domain_name
}

output "demo_object_key" {
  description = "Key of the demo S3 object"
  value       = aws_s3_object.demo_object.key
}

output "aws_region" {
  description = "AWS region used for deployment"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "project_name" {
  description = "Project name"
  value       = var.project_name
}

# Backend-related outputs
output "terraform_state_bucket" {
  description = "Name of the S3 bucket for Terraform state"
  value       = aws_s3_bucket.terraform_state.id
}

output "terraform_state_bucket_arn" {
  description = "ARN of the S3 bucket for Terraform state"
  value       = aws_s3_bucket.terraform_state.arn
}

output "terraform_state_lock_table" {
  description = "Name of the DynamoDB table for Terraform state locking"
  value       = aws_dynamodb_table.terraform_state_lock.name
}

output "terraform_state_lock_table_arn" {
  description = "ARN of the DynamoDB table for Terraform state locking"
  value       = aws_dynamodb_table.terraform_state_lock.arn
}