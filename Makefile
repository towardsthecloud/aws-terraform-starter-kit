.PHONY: help init plan apply destroy validate format clean

# Default target
help:
	@echo "Available targets:"
	@echo "  init      - Initialize Terraform"
	@echo "  validate  - Validate Terraform configuration"
	@echo "  format    - Format Terraform files"
	@echo "  plan      - Create Terraform plan"
	@echo "  apply     - Apply Terraform changes"
	@echo "  destroy   - Destroy Terraform resources"
	@echo "  clean     - Clean Terraform files"
	@echo "  setup     - Initial setup (copy example files)"

# Initialize Terraform
init:
	terraform init

# Validate Terraform configuration
validate:
	terraform validate

# Format Terraform files
format:
	terraform fmt -recursive

# Create Terraform plan
plan:
	terraform plan

# Apply Terraform changes
apply:
	terraform apply

# Destroy Terraform resources
destroy:
	terraform destroy

# Clean Terraform files
clean:
	rm -rf .terraform/
	rm -f .terraform.lock.hcl
	rm -f terraform.tfstate*
	rm -f *.tfplan

# Initial setup
setup:
	@if [ ! -f terraform.tfvars ]; then \
		cp terraform.tfvars.example terraform.tfvars; \
		echo "Created terraform.tfvars from example file"; \
		echo "Please edit terraform.tfvars with your specific values"; \
	else \
		echo "terraform.tfvars already exists"; \
	fi

# Full workflow for first deployment
deploy: setup init validate format plan apply

# Check Terraform and AWS CLI versions
check:
	@echo "Checking required tools..."
	@terraform version
	@aws --version
	@echo "All tools are available!"