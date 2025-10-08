#!/bin/bash

# AWS Terraform Starter Kit - Cleanup Script
# This script helps clean up resources and local files

set -e

echo "🧹 AWS Terraform Starter Kit Cleanup"
echo "===================================="

# Function to destroy resources
destroy_resources() {
    echo "This will destroy all resources created by Terraform."
    echo "This action cannot be undone!"
    echo ""
    
    if [ -f terraform.tfstate ]; then
        terraform plan -destroy
        echo ""
        read -p "Do you want to destroy these resources? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            terraform destroy -auto-approve
            echo "✅ Resources destroyed"
        else
            echo "❌ Destruction cancelled"
            return 1
        fi
    else
        echo "ℹ️  No terraform.tfstate file found. No resources to destroy."
    fi
}

# Function to clean local files
clean_local() {
    echo "Cleaning local Terraform files..."
    
    # Remove Terraform files
    if [ -d .terraform ]; then
        rm -rf .terraform/
        echo "✅ Removed .terraform directory"
    fi
    
    if [ -f .terraform.lock.hcl ]; then
        rm -f .terraform.lock.hcl
        echo "✅ Removed .terraform.lock.hcl"
    fi
    
    if [ -f terraform.tfstate.backup ]; then
        rm -f terraform.tfstate.backup
        echo "✅ Removed terraform.tfstate.backup"
    fi
    
    if [ -f tfplan ]; then
        rm -f tfplan
        echo "✅ Removed tfplan"
    fi
    
    echo "✅ Local cleanup completed"
}

# Main cleanup function
main() {
    echo "Select cleanup option:"
    echo "1. Destroy AWS resources only"
    echo "2. Clean local files only"
    echo "3. Full cleanup (destroy resources + clean local files)"
    echo "4. Cancel"
    echo ""
    read -p "Enter your choice (1-4): " -n 1 -r
    echo ""
    
    case $REPLY in
        1)
            destroy_resources
            ;;
        2)
            clean_local
            ;;
        3)
            destroy_resources && clean_local
            ;;
        4)
            echo "❌ Cleanup cancelled"
            exit 0
            ;;
        *)
            echo "❌ Invalid option"
            exit 1
            ;;
    esac
    
    echo ""
    echo "🎉 Cleanup completed!"
}

# Run main function
main "$@"