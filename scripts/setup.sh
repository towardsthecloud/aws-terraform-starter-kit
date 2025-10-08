#!/bin/bash

# AWS Terraform Starter Kit - Setup Script
# This script helps set up the initial environment

set -e

echo "🚀 AWS Terraform Starter Kit Setup"
echo "================================="

# Check if required tools are installed
echo "Checking required tools..."

# Check Terraform
if ! command -v terraform &> /dev/null; then
    echo "❌ Terraform is not installed. Please install Terraform first."
    echo "   Visit: https://learn.hashicorp.com/tutorials/terraform/install-cli"
    exit 1
fi

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI is not installed. Please install AWS CLI first."
    echo "   Visit: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
    exit 1
fi

echo "✅ All required tools are installed"

# Display versions
echo ""
echo "Tool versions:"
terraform version | head -1
aws --version

# Check AWS credentials
echo ""
echo "Checking AWS credentials..."
if aws sts get-caller-identity &> /dev/null; then
    echo "✅ AWS credentials are configured"
    aws sts get-caller-identity --output table
else
    echo "❌ AWS credentials are not configured"
    echo "   Please run: aws configure"
    echo "   Or set environment variables: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY"
    exit 1
fi

# Copy example files if they don't exist
echo ""
echo "Setting up configuration files..."
if [ ! -f terraform.tfvars ]; then
    cp terraform.tfvars.example terraform.tfvars
    echo "✅ Created terraform.tfvars from example"
    echo "   Please edit terraform.tfvars with your specific values"
else
    echo "ℹ️  terraform.tfvars already exists"
fi

echo ""
echo "🎉 Setup complete!"
echo ""
echo "Next steps:"
echo "1. Edit terraform.tfvars with your specific values"
echo "2. Run: make init"
echo "3. Run: make plan"
echo "4. Run: make apply"
echo ""
echo "Or use the full deploy command: make deploy"