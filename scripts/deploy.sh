#!/bin/bash

# AWS Terraform Starter Kit - Deploy Script
# This script automates the deployment process

set -e

echo "🚀 AWS Terraform Starter Kit Deployment"
echo "======================================="

# Function to check if terraform.tfvars exists
check_tfvars() {
    if [ ! -f terraform.tfvars ]; then
        echo "❌ terraform.tfvars not found"
        echo "   Please copy terraform.tfvars.example to terraform.tfvars and edit it"
        echo "   Or run: make setup"
        exit 1
    fi
}

# Function to initialize Terraform
init_terraform() {
    echo "Initializing Terraform..."
    terraform init
    echo "✅ Terraform initialized"
}

# Function to validate configuration
validate_terraform() {
    echo "Validating Terraform configuration..."
    terraform validate
    echo "✅ Configuration is valid"
}

# Function to format files
format_terraform() {
    echo "Formatting Terraform files..."
    terraform fmt -recursive
    echo "✅ Files formatted"
}

# Function to create plan
plan_terraform() {
    echo "Creating Terraform plan..."
    terraform plan -out=tfplan
    echo "✅ Plan created"
}

# Function to apply changes
apply_terraform() {
    echo "Applying Terraform changes..."
    read -p "Do you want to apply these changes? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        terraform apply tfplan
        echo "✅ Changes applied successfully!"
        
        # Display outputs
        echo ""
        echo "📋 Deployment Outputs:"
        terraform output
    else
        echo "❌ Deployment cancelled"
        rm -f tfplan
        exit 1
    fi
}

# Main deployment flow
main() {
    check_tfvars
    init_terraform
    validate_terraform
    format_terraform
    plan_terraform
    apply_terraform
    
    echo ""
    echo "🎉 Deployment completed successfully!"
    echo ""
    echo "Your S3 bucket has been created and is ready to use."
    echo "Check the outputs above for details."
}

# Run main function
main "$@"