terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }

  # Backend configuration for state management
  # Uncomment and configure after creating the S3 bucket and DynamoDB table
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "terraform/state.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "terraform-state-lock"
  #   encrypt        = true
  # }
}