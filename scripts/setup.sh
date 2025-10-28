#!/usr/bin/env bash

# Terraform AWS Starter Kit - Unified Setup Script
# This script bootstraps your entire Terraform infrastructure in one go

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Helper functions
info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
    exit 1
}

section() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Banner
echo -e "${MAGENTA}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                            ║
║     Terraform AWS Starter Kit - Unified Setup             ║
║                                                            ║
║     Bootstrap → Provision → Deploy OIDC                   ║
║                                                            ║
╚═══════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Complete setup wizard for Terraform AWS Starter Kit.
Bootstraps backend, provisions environments, and deploys OIDC.

OPTIONS:
    -e, --environments ENV1,ENV2  Comma-separated list of environments (test,staging,production)
    -p, --profile PROFILE         AWS profile to use (granted/assume profile name)
    -a, --auto-approve            Skip all interactive confirmations
    -s, --skip-bootstrap          Skip bootstrap step (use existing backend)
    -d, --skip-deploy             Skip OIDC deployment (only create files)
    -h, --help                    Display this help message

EXAMPLES:
    # Interactive setup (recommended for first time)
    $0

    # Automated setup for test environment
    $0 -e test -a

    # Setup multiple environments
    $0 -e test,staging,production

    # Setup with AWS profile
    $0 -p production-admin

    # Skip bootstrap (if already done)
    $0 -s

EOF
    exit 0
}

# Parse command line arguments
ENVIRONMENTS_ARG=""
AWS_PROFILE=""
AUTO_APPROVE=false
SKIP_BOOTSTRAP=false
SKIP_DEPLOY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--environments)
            ENVIRONMENTS_ARG="$2"
            shift 2
            ;;
        -p|--profile)
            AWS_PROFILE="$2"
            shift 2
            ;;
        -a|--auto-approve)
            AUTO_APPROVE=true
            shift
            ;;
        -s|--skip-bootstrap)
            SKIP_BOOTSTRAP=true
            shift
            ;;
        -d|--skip-deploy)
            SKIP_DEPLOY=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            error "Unknown option: $1\nUse -h or --help for usage information."
            ;;
    esac
done

# Get repository root
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

#######################################
# Step 1: Prerequisites Check
#######################################
section "Step 1/4: Prerequisites Check"

info "Checking required tools..."

# Check AWS CLI installation
if ! command -v aws &> /dev/null; then
    error "AWS CLI is not installed. Please install from https://aws.amazon.com/cli/"
fi
success "AWS CLI found: $(aws --version 2>&1 | head -1)"

# Check Terraform installation
if ! command -v terraform &> /dev/null; then
    error "Terraform is not installed. Please install from https://www.terraform.io/downloads.html"
fi
TF_VERSION=$(terraform version -json 2>/dev/null | grep -o '"terraform_version": "[^"]*' | cut -d'"' -f4 || terraform version | head -1)
success "Terraform found: $TF_VERSION"

# Check Git installation
if ! command -v git &> /dev/null; then
    error "Git is not installed. Please install Git."
fi
success "Git found: $(git --version)"

# Unset AWS_PROFILE if it's empty
if [[ -z "${AWS_PROFILE:-}" ]]; then
    unset AWS_PROFILE 2>/dev/null || true
fi

# Configure AWS credentials
if [[ -n "${AWS_PROFILE:-}" ]]; then
    info "Using AWS profile: $AWS_PROFILE"
    export AWS_PROFILE="$AWS_PROFILE"

    # Check if Granted (assume) is available
    if command -v assume &> /dev/null; then
        info "Granted detected. Make sure you have assumed the role."
    fi
fi

# Verify AWS credentials
info "Verifying AWS credentials..."
if ! aws sts get-caller-identity &> /dev/null; then
    error "AWS credentials not configured. Please configure AWS CLI or use Granted (assume)."
fi

CALLER_IDENTITY=$(aws sts get-caller-identity)
ACCOUNT_ID=$(echo "$CALLER_IDENTITY" | grep -o '"Account": "[^"]*' | cut -d'"' -f4)
USER_ARN=$(echo "$CALLER_IDENTITY" | grep -o '"Arn": "[^"]*' | cut -d'"' -f4)

success "AWS credentials verified"
info "Account ID: $ACCOUNT_ID"
info "Identity: $USER_ARN"

#######################################
# Step 2: Backend Bootstrap
#######################################
section "Step 2/4: Backend Bootstrap (S3 + DynamoDB)"

# Check if backend configuration already exists
BACKEND_CONFIG_FILE="$REPO_ROOT/.terraform-backend.conf"
BOOTSTRAP_DONE=false

if [[ -f "$BACKEND_CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$BACKEND_CONFIG_FILE"
    success "Found existing backend configuration"
    info "S3 Bucket: ${TF_STATE_BUCKET}"
    info "DynamoDB Table: ${TF_STATE_LOCK_TABLE}"
    info "Region: ${AWS_REGION}"
    BOOTSTRAP_DONE=true

    if [[ "$SKIP_BOOTSTRAP" == false && "$AUTO_APPROVE" == false ]]; then
        echo ""
        read -r -p "Backend already configured. Skip bootstrap? [Y/n]: " SKIP_CONFIRM
        SKIP_CONFIRM=${SKIP_CONFIRM:-Y}
        if [[ "$SKIP_CONFIRM" =~ ^[Yy]$ ]]; then
            SKIP_BOOTSTRAP=true
        fi
    else
        SKIP_BOOTSTRAP=true
    fi
fi

if [[ "$SKIP_BOOTSTRAP" == false ]]; then
    info "Setting up Terraform backend resources..."
    echo ""

    # AWS Region - auto-detect from environment or AWS CLI
    DETECTED_REGION="${AWS_REGION:-}"
    if [[ -z "$DETECTED_REGION" ]]; then
        DETECTED_REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
    fi

    if [[ "$AUTO_APPROVE" == false ]]; then
        read -r -p "Enter AWS region [$DETECTED_REGION]: " INPUT_REGION
        AWS_REGION=${INPUT_REGION:-$DETECTED_REGION}
    else
        AWS_REGION=$DETECTED_REGION
    fi

    # S3 Bucket Name
    DEFAULT_BUCKET="terraform-state-${ACCOUNT_ID}-${AWS_REGION}"
    if [[ "$AUTO_APPROVE" == false ]]; then
        read -r -p "Enter S3 bucket name [$DEFAULT_BUCKET]: " BUCKET_NAME
        BUCKET_NAME=${BUCKET_NAME:-$DEFAULT_BUCKET}
    else
        BUCKET_NAME=$DEFAULT_BUCKET
    fi

    # DynamoDB Table Name
    DEFAULT_TABLE="terraform-state-lock"
    if [[ "$AUTO_APPROVE" == false ]]; then
        read -r -p "Enter DynamoDB table name [$DEFAULT_TABLE]: " TABLE_NAME
        TABLE_NAME=${TABLE_NAME:-$DEFAULT_TABLE}
    else
        TABLE_NAME=$DEFAULT_TABLE
    fi

    # Summary
    echo ""
    info "Configuration summary:"
    echo "  Region: $AWS_REGION"
    echo "  S3 Bucket: $BUCKET_NAME"
    echo "  DynamoDB Table: $TABLE_NAME"
    echo "  Versioning: Enabled (mandatory for state safety)"
    echo ""

    if [[ "$AUTO_APPROVE" == false ]]; then
        read -r -p "Proceed with backend creation? [y/N] " CONFIRM
        if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
            info "Bootstrap cancelled by user."
            exit 0
        fi
    fi

    echo ""

    # Create S3 bucket
    info "Creating S3 bucket: $BUCKET_NAME"

    if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
        warning "S3 bucket '$BUCKET_NAME' already exists. Skipping creation."
    else
        # Create bucket with location constraint if not in us-east-1
        if [[ "$AWS_REGION" == "us-east-1" ]]; then
            aws s3api create-bucket \
                --bucket "$BUCKET_NAME" \
                --region "$AWS_REGION"
        else
            aws s3api create-bucket \
                --bucket "$BUCKET_NAME" \
                --region "$AWS_REGION" \
                --create-bucket-configuration LocationConstraint="$AWS_REGION"
        fi
        success "S3 bucket created successfully"
    fi

    # Enable versioning (mandatory for Terraform state safety)
    info "Enabling S3 versioning..."
    aws s3api put-bucket-versioning \
        --bucket "$BUCKET_NAME" \
        --versioning-configuration Status=Enabled \
        --region "$AWS_REGION"

    # Verify versioning is enabled
    VERSIONING_STATUS=$(aws s3api get-bucket-versioning \
        --bucket "$BUCKET_NAME" \
        --region "$AWS_REGION" \
        --query 'Status' \
        --output text)

    if [[ "$VERSIONING_STATUS" == "Enabled" ]]; then
        success "S3 versioning enabled and verified"
    else
        error "Failed to enable S3 versioning. Current status: $VERSIONING_STATUS"
    fi

    # Enable server-side encryption
    info "Enabling server-side encryption (AES256)..."
    aws s3api put-bucket-encryption \
        --bucket "$BUCKET_NAME" \
        --server-side-encryption-configuration '{
            "Rules": [{
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                },
                "BucketKeyEnabled": true
            }]
        }' \
        --region "$AWS_REGION"
    success "Server-side encryption enabled"

    # Block public access
    info "Blocking public access..."
    aws s3api put-public-access-block \
        --bucket "$BUCKET_NAME" \
        --public-access-block-configuration \
            "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" \
        --region "$AWS_REGION"
    success "Public access blocked"

    # Add bucket policy for secure access
    info "Adding bucket policy..."
    BUCKET_POLICY=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "EnforcedTLS",
            "Effect": "Deny",
            "Principal": "*",
            "Action": "s3:*",
            "Resource": [
                "arn:aws:s3:::${BUCKET_NAME}",
                "arn:aws:s3:::${BUCKET_NAME}/*"
            ],
            "Condition": {
                "Bool": {
                    "aws:SecureTransport": "false"
                }
            }
        }
    ]
}
EOF
)

    echo "$BUCKET_POLICY" | aws s3api put-bucket-policy \
        --bucket "$BUCKET_NAME" \
        --policy file:///dev/stdin \
        --region "$AWS_REGION"
    success "Bucket policy applied"

    # Add bucket tags
    info "Adding bucket tags..."
    aws s3api put-bucket-tagging \
        --bucket "$BUCKET_NAME" \
        --tagging "TagSet=[
            {Key=Name,Value=${BUCKET_NAME}},
            {Key=Purpose,Value=TerraformState},
            {Key=ManagedBy,Value=setup-script}
        ]" \
        --region "$AWS_REGION"
    success "Bucket tags added"

    # Create DynamoDB table
    info "Creating DynamoDB table: $TABLE_NAME"

    if aws dynamodb describe-table --table-name "$TABLE_NAME" --region "$AWS_REGION" &>/dev/null; then
        warning "DynamoDB table '$TABLE_NAME' already exists. Skipping creation."
    else
        aws dynamodb create-table \
            --table-name "$TABLE_NAME" \
            --attribute-definitions AttributeName=LockID,AttributeType=S \
            --key-schema AttributeName=LockID,KeyType=HASH \
            --billing-mode PAY_PER_REQUEST \
            --tags Key=Name,Value="$TABLE_NAME" Key=Purpose,Value=TerraformStateLock Key=ManagedBy,Value=setup-script \
            --region "$AWS_REGION"

        info "Waiting for DynamoDB table to become active..."
        aws dynamodb wait table-exists --table-name "$TABLE_NAME" --region "$AWS_REGION"
        success "DynamoDB table created successfully"
    fi

    # Save backend configuration to a file for easy reference
    info "Saving backend configuration to: $BACKEND_CONFIG_FILE"

    cat > "$BACKEND_CONFIG_FILE" << EOF
# Terraform Backend Configuration
# Generated by setup.sh on $(date)

TF_STATE_BUCKET=$BUCKET_NAME
TF_STATE_LOCK_TABLE=$TABLE_NAME
AWS_REGION=$AWS_REGION
EOF

    success "Backend configuration saved"

    # Load the variables we just saved
    TF_STATE_BUCKET=$BUCKET_NAME
    TF_STATE_LOCK_TABLE=$TABLE_NAME
    BOOTSTRAP_DONE=true
else
    info "Skipping bootstrap (using existing backend)"
fi

#######################################
# Step 3: Environment Provisioning
#######################################
section "Step 3/4: Environment Provisioning"

# Auto-detect GitHub repository name from git remote
DETECTED_REPO=""
if git remote get-url origin &>/dev/null; then
    REMOTE_URL=$(git remote get-url origin)
    if [[ "$REMOTE_URL" =~ github\.com[:/]([^/]+)/([^/\.]+)(\.git)?$ ]]; then
        DETECTED_REPO="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
    fi
fi

# Prompt for GitHub repository name
if [[ "$AUTO_APPROVE" == false ]]; then
    if [[ -n "$DETECTED_REPO" ]]; then
        info "Enter your GitHub repository name [$DETECTED_REPO]:"
    else
        info "Enter your GitHub repository name (e.g., username/terraform-starter-kit):"
    fi
    read -r INPUT_REPO
    GITHUB_REPO=${INPUT_REPO:-$DETECTED_REPO}
else
    GITHUB_REPO=${DETECTED_REPO}
fi

if [[ -z "$GITHUB_REPO" ]]; then
    error "GitHub repository name cannot be empty!"
fi

# Validate repository format
if [[ ! "$GITHUB_REPO" =~ ^[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+$ ]]; then
    error "Invalid repository format. Use: username/repository-name"
fi

success "GitHub repository: $GITHUB_REPO"

# Determine which environments to provision
ENVIRONMENTS=()
if [[ -n "$ENVIRONMENTS_ARG" ]]; then
    # Use provided environments
    IFS=',' read -ra ENVIRONMENTS <<< "$ENVIRONMENTS_ARG"
else
    # Interactive selection
    if [[ "$AUTO_APPROVE" == false ]]; then
        echo ""
        warning "⚠️  IMPORTANT: Multi-Account Best Practice"
        echo ""
        echo "For production use, each environment should be in a SEPARATE AWS account:"
        echo "  • Test → AWS Account A"
        echo "  • Staging → AWS Account B"
        echo "  • Production → AWS Account C"
        echo ""
        echo "This setup script configures ONE environment in the CURRENT AWS account."
        echo "To set up multiple environments, run this script separately in each account."
        echo ""
        info "Select environment to provision in account $ACCOUNT_ID:"
        echo "  1) test"
        echo "  2) staging"
        echo "  3) production"
        read -r -p "Enter choice [1]: " ENV_CHOICE
        ENV_CHOICE=${ENV_CHOICE:-1}

        case $ENV_CHOICE in
            1) ENVIRONMENTS+=("test") ;;
            2) ENVIRONMENTS+=("staging") ;;
            3) ENVIRONMENTS+=("production") ;;
            *) error "Invalid choice: $ENV_CHOICE" ;;
        esac
    else
        # Default to test for auto-approve
        ENVIRONMENTS=("test")
    fi
fi

# Warn if multiple environments selected
if [[ ${#ENVIRONMENTS[@]} -gt 1 ]]; then
    echo ""
    warning "⚠️  WARNING: Multiple environments in one AWS account"
    warning "You are creating ${#ENVIRONMENTS[@]} environments in account $ACCOUNT_ID"
    warning ""
    warning "This is NOT recommended for production use!"
    warning "Best practice: One environment per AWS account for security isolation"
    echo ""
    read -r -p "Continue anyway? (yes/N): " CONFIRM
    if [[ "$CONFIRM" != "yes" ]]; then
        info "Setup cancelled. Run this script separately in each AWS account."
        exit 0
    fi
fi

if [[ ${#ENVIRONMENTS[@]} -eq 0 ]]; then
    error "No environments selected!"
fi

success "Will provision: ${ENVIRONMENTS[*]}"

# Detect AWS region for use in environments
DETECTED_REGION="${AWS_REGION:-}"
if [[ -z "$DETECTED_REGION" ]]; then
    DETECTED_REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
fi

# Function to provision a single environment
provision_environment() {
    local ENVIRONMENT=$1
    local USE_EXISTING_OIDC=$2  # Pass whether to use existing OIDC provider

    echo ""
    info "========================================="
    info "Provisioning environment: $ENVIRONMENT"
    info "========================================="

    # Create environment directory structure
    ENV_DIR="$REPO_ROOT/environments/$ENVIRONMENT"
    info "Creating environment directory: $ENV_DIR"
    mkdir -p "$ENV_DIR"

    # Create backend.tf
    info "Creating backend.tf..."
    cat > "$ENV_DIR/backend.tf" << EOF
terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "${TF_STATE_BUCKET}"
    key            = "environments/${ENVIRONMENT}/terraform.tfstate"
    region         = "${AWS_REGION}"
    encrypt        = true
    dynamodb_table = "${TF_STATE_LOCK_TABLE}"
  }
}
EOF
    success "Created backend.tf"

    # Create terraform.tfvars
    info "Creating terraform.tfvars..."
    cat > "$ENV_DIR/terraform.tfvars" << EOF
# GitHub repository for OIDC provider
github_repo = "$GITHUB_REPO"

# Set to true if the OIDC provider already exists in your AWS account
# This prevents creating duplicate OIDC providers
use_existing_oidc_provider = $USE_EXISTING_OIDC

# IAM role name for GitHub Actions
role_name = "GitHubActionsServiceRole-Terraform"

# Managed policy ARNs to attach to the role
# WARNING: AdministratorAccess is used for demo purposes only
# In production, use least-privilege permissions
managed_policy_arns = [
  "arn:aws:iam::aws:policy/AdministratorAccess"
]

# Optional: IAM path for the role
# path = "/github-actions/"

# Optional: Additional audience for OIDC
# audience_list = ["sts.amazonaws.com"]
EOF
    success "Created terraform.tfvars"

    # Create main.tf
    info "Creating main.tf..."
    cat > "$ENV_DIR/main.tf" << EOF
# Configure the AWS Provider
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = "$ENVIRONMENT"
      ManagedBy   = "terraform"
      Repository  = "$GITHUB_REPO"
    }
  }
}

# OIDC Provider Module
module "oidc_provider" {
  source = "../../modules/oidc-provider"

  use_existing_oidc_provider = var.use_existing_oidc_provider
  github_repo                = var.github_repo
  role_name                  = var.role_name
  managed_policy_arns        = var.managed_policy_arns
}
EOF
    success "Created main.tf"

    # Create variables.tf
    info "Creating variables.tf..."
    cat > "$ENV_DIR/variables.tf" << EOF
variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "${DETECTED_REGION}"
}

variable "use_existing_oidc_provider" {
  description = "Whether to use an existing OIDC provider or create a new one"
  type        = bool
  default     = true
}

variable "github_repo" {
  description = "GitHub repository name (format: owner/repo)"
  type        = string
  default     = "$GITHUB_REPO"
}

variable "role_name" {
  description = "Name of the IAM role for GitHub Actions"
  type        = string
  default     = "GitHubActionsServiceRole-Terraform"
}

variable "managed_policy_arns" {
  description = "List of IAM policy ARNs to attach to the role"
  type        = list(string)
  default = [
    "arn:aws:iam::aws:policy/AdministratorAccess"
  ]
}
EOF
    success "Created variables.tf"

    # Create outputs.tf
    info "Creating outputs.tf..."
    cat > "$ENV_DIR/outputs.tf" << EOF
output "oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider"
  value       = module.oidc_provider.oidc_provider_arn
}

output "role_arn" {
  description = "ARN of the GitHub Actions IAM role"
  value       = module.oidc_provider.role_arn
}

output "role_name" {
  description = "Name of the GitHub Actions IAM role"
  value       = module.oidc_provider.role_name
}
EOF
    success "Created outputs.tf"

    # Create GitHub Actions workflow
    WORKFLOW_FILE="$REPO_ROOT/.github/workflows/terraform-deploy-${ENVIRONMENT}.yml"
    info "Creating GitHub Actions workflow: $WORKFLOW_FILE"

    ENV_CAPITALIZED="$(tr '[:lower:]' '[:upper:]' <<< "${ENVIRONMENT:0:1}")${ENVIRONMENT:1}"

    mkdir -p "$REPO_ROOT/.github/workflows"

    cat > "$WORKFLOW_FILE" << EOF
name: Terraform Deploy - ${ENV_CAPITALIZED} Environment

on:
  push:
    branches:
      - main
    paths:
      - 'environments/${ENVIRONMENT}/**'
      - 'modules/**'
      - '.github/workflows/terraform-deploy-${ENVIRONMENT}.yml'
  pull_request_target:
    branches:
      - main
  workflow_dispatch:

permissions:
  id-token: write
  contents: read
  pull-requests: write

env:
  AWS_ACCOUNT_ID: \${{ vars.AWS_ACCOUNT_ID || '${ACCOUNT_ID}' }}
  AWS_REGION: \${{ vars.AWS_REGION || '${DETECTED_REGION}' }}
  GITHUB_ACTIONS_ROLE_NAME: \${{ vars.GITHUB_ACTIONS_ROLE_NAME || 'GitHubActionsServiceRole-Terraform' }}
  ENVIRONMENT: ${ENVIRONMENT}
  TF_WORKING_DIR: environments/${ENVIRONMENT}
  TF_STATE_BUCKET: \${{ vars.TF_STATE_BUCKET || '${TF_STATE_BUCKET}' }}
  TF_STATE_LOCK_TABLE: \${{ vars.TF_STATE_LOCK_TABLE || '${TF_STATE_LOCK_TABLE}' }}

jobs:
  tflint:
    name: TFLint Scan
    uses: ./.github/workflows/tflint-scan.yml

  checkov:
    name: Checkov Security Scan
    uses: ./.github/workflows/checkov-scan.yml
    with:
      working_directory: 'environments/${ENVIRONMENT}'
      soft_fail: true

  terraform-check:
    name: Terraform Check
    runs-on: ubuntu-latest
    needs: [tflint, checkov]

    defaults:
      run:
        working-directory: 'environments/${ENVIRONMENT}'

    steps:
      - name: Checkout code
        uses: actions/checkout@v5
        with:
          ref: \${{ github.event_name == 'pull_request_target' && github.event.pull_request.head.sha || github.sha }}

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3

      - name: Terraform Format Check
        run: terraform fmt -check -recursive

      - name: Terraform Init
        run: terraform init -backend=false

      - name: Terraform Validate
        run: terraform validate

  terraform-plan:
    name: Terraform Plan
    runs-on: ubuntu-latest
    needs: terraform-check
    if: github.event_name == 'pull_request_target'

    defaults:
      run:
        working-directory: 'environments/${ENVIRONMENT}'

    steps:
      - name: Checkout code
        uses: actions/checkout@v5
        with:
          ref: \${{ github.event_name == 'pull_request_target' && github.event.pull_request.head.sha || github.sha }}

      - name: Configure AWS credentials (OIDC)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::\${{ env.AWS_ACCOUNT_ID }}:role/\${{ env.GITHUB_ACTIONS_ROLE_NAME }}
          aws-region: \${{ env.AWS_REGION }}
          role-session-name: GitHubActions-Terraform-Plan-${ENV_CAPITALIZED}

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3

      - name: Terraform Init
        run: |
          terraform init \\
            -backend-config="bucket=\${{ env.TF_STATE_BUCKET }}" \\
            -backend-config="key=environments/${ENVIRONMENT}/terraform.tfstate" \\
            -backend-config="region=\${{ env.AWS_REGION }}" \\
            -backend-config="dynamodb_table=\${{ env.TF_STATE_LOCK_TABLE }}"

      - name: Terraform Plan
        run: terraform plan -out=tfplan.binary
        continue-on-error: true

      - name: Save Plan Artifact
        if: always()
        uses: actions/upload-artifact@v5
        with:
          name: terraform-plan-artifact
          path: \${{ env.TF_WORKING_DIR }}/tfplan.binary
          retention-days: 1

  plan-comment:
    name: Post Plan Comment
    needs: terraform-plan
    if: github.event_name == 'pull_request_target'
    uses: ./.github/workflows/terraform-plan-pr-comment.yml
    with:
      planfile: tfplan.binary
      working-directory: 'environments/${ENVIRONMENT}'
      aws-region: ${DETECTED_REGION}
      environment: ${ENVIRONMENT}

  terraform-apply:
    name: Terraform Apply
    runs-on: ubuntu-latest
    needs: terraform-check
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    environment: ${ENVIRONMENT}

    defaults:
      run:
        working-directory: 'environments/${ENVIRONMENT}'

    steps:
      - name: Checkout code
        uses: actions/checkout@v5

      - name: Configure AWS credentials (OIDC)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::\${{ env.AWS_ACCOUNT_ID }}:role/\${{ env.GITHUB_ACTIONS_ROLE_NAME }}
          aws-region: \${{ env.AWS_REGION }}
          role-session-name: GitHubActions-Terraform-Apply-${ENV_CAPITALIZED}

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3

      - name: Terraform Init
        run: |
          terraform init \\
            -backend-config="bucket=\${{ env.TF_STATE_BUCKET }}" \\
            -backend-config="key=environments/${ENVIRONMENT}/terraform.tfstate" \\
            -backend-config="region=\${{ env.AWS_REGION }}" \\
            -backend-config="dynamodb_table=\${{ env.TF_STATE_LOCK_TABLE }}"

      - name: Terraform Apply
        run: terraform apply -auto-approve

      - name: Terraform Output
        if: success()
        run: |
          echo "### Terraform Outputs :rocket:" >> \$GITHUB_STEP_SUMMARY
          echo "" >> \$GITHUB_STEP_SUMMARY
          echo '\`\`\`' >> \$GITHUB_STEP_SUMMARY
          terraform output >> \$GITHUB_STEP_SUMMARY
          echo '\`\`\`' >> \$GITHUB_STEP_SUMMARY

      - name: Deployment Status
        if: always()
        run: |
          if [ \$? -eq 0 ]; then
            echo "✅ Deployment to ${ENVIRONMENT} environment successful!" >> \$GITHUB_STEP_SUMMARY
          else
            echo "❌ Deployment to ${ENVIRONMENT} environment failed!" >> \$GITHUB_STEP_SUMMARY
          fi
EOF
    success "Created GitHub Actions workflow"

    success "Environment $ENVIRONMENT provisioned successfully!"
}

# Check if OIDC provider exists before provisioning
info "Checking if GitHub OIDC provider exists in account $ACCOUNT_ID..."
OIDC_PROVIDER_URL="https://token.actions.githubusercontent.com"
EXISTING_PROVIDER=$(aws iam list-open-id-connect-providers --output json 2>/dev/null | grep -o "arn:aws:iam::[0-9]*:oidc-provider/token.actions.githubusercontent.com" || true)

if [[ -n "$EXISTING_PROVIDER" ]]; then
    success "Found existing OIDC provider: $EXISTING_PROVIDER"
    info "This provider will be used by the environment(s)"
    OIDC_EXISTS=true
else
    info "No existing OIDC provider found"
    info "The first environment will create a new OIDC provider"
    OIDC_EXISTS=false
fi

# Provision each environment
FIRST_ENV=true
for ENV in "${ENVIRONMENTS[@]}"; do
    # Logic for OIDC provider management:
    # - If OIDC already exists (manually created or from another setup): use it (don't manage it)
    # - If no OIDC exists and this is first environment: create and manage it
    # - If OIDC will be created by first env: subsequent envs use it

    if [[ "$OIDC_EXISTS" == true ]]; then
        USE_EXISTING="true"
        info "Environment '$ENV' will use existing OIDC provider (not managed by Terraform)"
    elif [[ "$FIRST_ENV" == true ]]; then
        USE_EXISTING="false"
        info "Environment '$ENV' will create and manage the OIDC provider"
        OIDC_EXISTS=true  # Mark as will exist after first env
    else
        USE_EXISTING="true"
        info "Environment '$ENV' will use OIDC provider created by first environment"
    fi

    provision_environment "$ENV" "$USE_EXISTING"
    FIRST_ENV=false
done

#######################################
# Step 4: OIDC Deployment
#######################################
section "Step 4/4: OIDC Deployment"

if [[ "$SKIP_DEPLOY" == true ]]; then
    warning "Skipping OIDC deployment (files created only)"
else
    # Deploy OIDC for each environment
    FIRST_OIDC=true

    for ENV in "${ENVIRONMENTS[@]}"; do
        echo ""
        info "========================================="
        info "Deploying OIDC for environment: $ENV"
        info "========================================="

        ENV_DIR="$REPO_ROOT/environments/$ENV"
        cd "$ENV_DIR"

        # Terraform Init
        info "Initializing Terraform..."
        terraform init
        success "Terraform initialized"

        # Terraform Validate
        info "Validating Terraform configuration..."
        terraform validate
        success "Configuration is valid"

        # Check if OIDC provider already exists (only need to create once)
        if [[ "$FIRST_OIDC" == true ]]; then
            info "Checking for existing GitHub OIDC provider..."
            OIDC_PROVIDER_URL="https://token.actions.githubusercontent.com"
            EXISTING_PROVIDER=$(aws iam list-open-id-connect-providers --output json | grep -o "arn:aws:iam::[0-9]*:oidc-provider/token.actions.githubusercontent.com" || true)

            if [[ -n "$EXISTING_PROVIDER" ]]; then
                success "Found existing OIDC provider: $EXISTING_PROVIDER"
            else
                info "No existing OIDC provider found, will create new one"
            fi
        fi

        # Terraform Plan
        info "Creating deployment plan..."
        PLAN_OUTPUT=$(terraform plan -out=tfplan -var-file=terraform.tfvars 2>&1 || true)

        if echo "$PLAN_OUTPUT" | grep -q "No changes"; then
            success "No changes detected for $ENV. Infrastructure is up to date."
            rm -f tfplan
        else
            echo "$PLAN_OUTPUT"

            # Interactive approval (unless auto-approve is set)
            if [[ "$AUTO_APPROVE" == false ]]; then
                echo ""
                warning "Review the plan above carefully."
                read -r -p "Do you want to apply these changes for $ENV? [y/N] " CONFIRM

                if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
                    info "Deployment cancelled for $ENV."
                    rm -f tfplan
                    continue
                fi
            fi

            # Terraform Apply
            info "Applying Terraform changes for $ENV..."
            if terraform apply -auto-approve tfplan; then
                success "OIDC deployed successfully for $ENV!"

                # Verify state was saved to S3
                info "Verifying state was saved to S3..."
                sleep 2  # Give S3 a moment to process the write

                if aws s3api head-object \
                    --bucket "$TF_STATE_BUCKET" \
                    --key "environments/$ENV/terraform.tfstate" \
                    --region "$AWS_REGION" &>/dev/null; then
                    success "State file confirmed in S3"

                    # Verify state contains expected resources
                    RESOURCE_COUNT=$(terraform state list | wc -l | tr -d ' ')
                    info "State contains $RESOURCE_COUNT resources"

                    if [[ $RESOURCE_COUNT -eq 0 ]]; then
                        error "State file is empty! Resources were created but state was not saved properly."
                    fi
                else
                    error "State file not found in S3! Apply may have failed to save state."
                fi

                # Display outputs
                echo ""
                info "Terraform Outputs for $ENV:"
                echo -e "${GREEN}"
                terraform output
                echo -e "${NC}"
            else
                error "Terraform apply failed for $ENV!"
            fi

            # Cleanup plan file
            rm -f tfplan
        fi

        FIRST_OIDC=false
    done

    cd "$REPO_ROOT"
fi

#######################################
# Final Summary
#######################################
echo ""
echo -e "${GREEN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                            ║
║              Setup Complete! 🎉                           ║
║                                                            ║
╚═══════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

echo ""
info "What was created:"
echo ""
echo "  ✅ S3 bucket: ${TF_STATE_BUCKET}"
echo "  ✅ DynamoDB table: ${TF_STATE_LOCK_TABLE}"
echo "  ✅ GitHub OIDC provider in AWS"
echo "  ✅ IAM role for GitHub Actions"
echo ""

for ENV in "${ENVIRONMENTS[@]}"; do
    echo "  ✅ Environment: $ENV"
    echo "     - Terraform files in environments/$ENV/"
    echo "     - GitHub workflow: .github/workflows/terraform-deploy-${ENV}.yml"
done

echo ""
info "GitHub Repository Variables (optional - defaults are embedded):"
echo ""
echo "  AWS_ACCOUNT_ID: $ACCOUNT_ID (hardcoded in workflows)"
echo "  AWS_REGION: ${DETECTED_REGION}"
echo "  TF_STATE_BUCKET: ${TF_STATE_BUCKET}"
echo "  TF_STATE_LOCK_TABLE: ${TF_STATE_LOCK_TABLE}"
echo "  GITHUB_ACTIONS_ROLE_NAME: GitHubActionsServiceRole-Terraform"
echo ""
warning "Note: These values are embedded as defaults in the workflows."
warning "You only need to set GitHub variables if you want to override them."
echo ""

info "Next Steps:"
echo ""
echo "1. Review generated files:"
for ENV in "${ENVIRONMENTS[@]}"; do
    echo "   - environments/${ENV}/terraform.tfvars"
done
echo ""
echo "2. (Optional) Configure GitHub Environment Protection:"
for ENV in "${ENVIRONMENTS[@]}"; do
    echo "   - Go to Settings → Environments → ${ENV}"
    echo "   - Add required reviewers for ${ENV} deployments"
done
echo ""
echo "3. (Optional) Set GitHub repository variables (if overriding defaults):"
echo "   - Go to Settings → Secrets and variables → Actions → Variables"
echo ""
echo "4. Commit and push your changes:"
echo "   git add ."
echo "   git commit -m 'Initial setup: Add infrastructure configuration'"
echo "   git push origin main"
echo ""
echo "5. Test with a pull request to trigger the CI/CD pipeline"
echo ""

success "Your AWS Terraform Starter Kit is ready! 🚀"
echo ""
