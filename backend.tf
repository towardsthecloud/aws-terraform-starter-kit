# Backend Configuration for Remote State Management
# This file contains Terraform configuration for setting up remote state storage

# S3 bucket for Terraform state
resource "aws_s3_bucket" "terraform_state" {
  bucket = "${var.project_name}-terraform-state-${random_string.state_suffix.result}"

  tags = merge(local.common_tags, {
    Name        = "${var.project_name}-terraform-state"
    Description = "S3 bucket for storing Terraform state"
    Purpose     = "terraform-state"
  })
}

# Random string for unique state bucket naming
resource "random_string" "state_suffix" {
  length  = 8
  special = false
  upper   = false
}

# S3 bucket versioning for state bucket
resource "aws_s3_bucket_versioning" "terraform_state_versioning" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption for state bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state_encryption" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket public access block for state bucket
resource "aws_s3_bucket_public_access_block" "terraform_state_pab" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# DynamoDB table for state locking
resource "aws_dynamodb_table" "terraform_state_lock" {
  name         = "${var.project_name}-terraform-state-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = merge(local.common_tags, {
    Name        = "${var.project_name}-terraform-state-lock"
    Description = "DynamoDB table for Terraform state locking"
    Purpose     = "terraform-state-lock"
  })
}