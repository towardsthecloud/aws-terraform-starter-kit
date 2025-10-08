# Configure the AWS Provider
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.tags
  }
}

# Data source to get current AWS account ID
data "aws_caller_identity" "current" {}

# Data source to get current AWS region
data "aws_region" "current" {}

# Generate a random string for unique bucket naming
resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

# Local values for consistent naming
locals {
  bucket_name = var.bucket_name != "" ? var.bucket_name : "${var.project_name}-${var.environment}-${random_string.bucket_suffix.result}"

  common_tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "terraform"
  })
}

# S3 bucket - our dummy resource for demonstration
resource "aws_s3_bucket" "demo_bucket" {
  bucket = local.bucket_name

  tags = merge(local.common_tags, {
    Name        = local.bucket_name
    Description = "Demo S3 bucket created by Terraform starter kit"
  })
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "demo_bucket_versioning" {
  bucket = aws_s3_bucket.demo_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "demo_bucket_encryption" {
  bucket = aws_s3_bucket.demo_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "demo_bucket_pab" {
  bucket = aws_s3_bucket.demo_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Example S3 object
resource "aws_s3_object" "demo_object" {
  bucket       = aws_s3_bucket.demo_bucket.id
  key          = "demo/hello-terraform.txt"
  content      = "Hello from Terraform! This is a demo object created by the AWS Terraform Starter Kit."
  content_type = "text/plain"

  tags = merge(local.common_tags, {
    Name = "demo-object"
  })
}