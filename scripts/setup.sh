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
║     Bootstrap → Provision → Deploy Stacks                 ║
║                                                            ║
╚═══════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Complete setup wizard for Terraform AWS Starter Kit.
Bootstraps backend, provisions stacks, and deploys bootstrap + environments.

OPTIONS:
    -e, --environments ENV1,ENV2  Comma-separated list of environments (test,staging,production)
    -p, --profile PROFILE         AWS profile to use (granted/assume profile name)
    -a, --auto-approve            Skip all interactive confirmations
    -s, --skip-bootstrap          Skip bootstrap step (use existing backend)
    -d, --skip-deploy             Skip Terraform deployment (only create files)
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

ENV_CONFIG_FILE="$REPO_ROOT/config/environments.json"
DEFAULT_ROLE_NAME="GitHubActionsServiceRole-Terraform"

ensure_environment_config_file() {
    mkdir -p "$REPO_ROOT/config"

    if [[ ! -f "$ENV_CONFIG_FILE" ]]; then
        cat > "$ENV_CONFIG_FILE" << 'EOF'
{
  "environments": {}
}
EOF
        success "Created environment mapping file: $ENV_CONFIG_FILE"
    fi
}

get_environment_config_value() {
    local env_name=$1
    local key=$2

    jq -r --arg env "$env_name" --arg key "$key" \
        '.environments[$env][$key] // empty' "$ENV_CONFIG_FILE"
}

upsert_environment_config() {
    local env_name=$1
    local account_id=$2
    local region=$3
    local state_bucket=$4
    local role_name=$5
    local tmp_file

    tmp_file=$(mktemp)
    jq --arg env "$env_name" \
       --arg account_id "$account_id" \
       --arg region "$region" \
       --arg state_bucket "$state_bucket" \
       --arg role_name "$role_name" \
       '.environments[$env] = {
          account_id: $account_id,
          region: $region,
          state_bucket: $state_bucket,
          role_name: $role_name
        }' "$ENV_CONFIG_FILE" > "$tmp_file"
    mv "$tmp_file" "$ENV_CONFIG_FILE"
}

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

# Check jq installation
if ! command -v jq &> /dev/null; then
    error "jq is not installed. Please install jq to manage environment/account mappings."
fi
success "jq found: $(jq --version)"

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
section "Step 2/4: Backend Bootstrap (S3 with Native Locking)"

# Check if backend configuration already exists
BACKEND_CONFIG_FILE="$REPO_ROOT/.terraform-backend.conf"
BOOTSTRAP_DONE=false

if [[ -f "$BACKEND_CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$BACKEND_CONFIG_FILE"
    success "Found existing backend configuration"
    info "S3 Bucket: ${TF_STATE_BUCKET}"
    info "Region: ${AWS_REGION}"
    info "Locking: S3 Native (.tflock files)"
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

    # Summary
    echo ""
    info "Configuration summary:"
    echo "  Region: $AWS_REGION"
    echo "  S3 Bucket: $BUCKET_NAME"
    echo "  Locking: S3 Native (.tflock files)"
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

    # Save backend configuration to a file for easy reference
    info "Saving backend configuration to: $BACKEND_CONFIG_FILE"

    cat > "$BACKEND_CONFIG_FILE" << EOF
# Terraform Backend Configuration
# Generated by setup.sh on $(date)
# Using S3 Native State Locking (Terraform 1.10+)

TF_STATE_BUCKET=$BUCKET_NAME
AWS_REGION=$AWS_REGION
EOF

    success "Backend configuration saved"

    # Load the variables we just saved
    TF_STATE_BUCKET=$BUCKET_NAME
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

ensure_environment_config_file
info "Using environment mapping file: $ENV_CONFIG_FILE"

# Create account-level bootstrap stack for shared identity resources
provision_bootstrap_identity_stack() {
    local BOOTSTRAP_DIR="$REPO_ROOT/bootstrap/account"

    info "Creating account bootstrap stack: $BOOTSTRAP_DIR"
    mkdir -p "$BOOTSTRAP_DIR"

    cat > "$BOOTSTRAP_DIR/backend.tf" << EOF
terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket       = "${TF_STATE_BUCKET}"
    key          = "bootstrap/account/terraform.tfstate"
    region       = "${AWS_REGION}"
    encrypt      = true
    use_lockfile = true
  }
}
EOF

    cat > "$BOOTSTRAP_DIR/main.tf" << EOF
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      ManagedBy  = "terraform"
      Repository = var.github_repo
      Scope      = "account-bootstrap"
    }
  }
}

resource "aws_iam_openid_connect_provider" "github_actions" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = var.audience_list
  thumbprint_list = [var.github_thumbprint]

  tags = {
    Name       = "GitHubActionsOIDCProvider"
    Repository = var.github_repo
  }
}
EOF

    cat > "$BOOTSTRAP_DIR/variables.tf" << EOF
variable "aws_region" {
  description = "AWS region for provider operations"
  type        = string
  default     = "${DETECTED_REGION}"
}

variable "github_repo" {
  description = "GitHub repository name (format: owner/repo)"
  type        = string
  default     = "${GITHUB_REPO}"
}

variable "github_thumbprint" {
  description = "GitHub OIDC thumbprint"
  type        = string
  default     = "6938fd4d98bab03faadb97b34396831e3780aea1"
}

variable "audience_list" {
  description = "List of allowed audiences for the OIDC provider"
  type        = list(string)
  default     = ["sts.amazonaws.com"]
}
EOF

    cat > "$BOOTSTRAP_DIR/outputs.tf" << EOF
output "oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider"
  value       = aws_iam_openid_connect_provider.github_actions.arn
}
EOF

    cat > "$BOOTSTRAP_DIR/terraform.tfvars" << EOF
aws_region  = "${DETECTED_REGION}"
github_repo = "${GITHUB_REPO}"
EOF

    success "Created account bootstrap stack files"
}

# Resolve account/region/state mapping for an environment and enforce account guardrails
resolve_environment_mapping() {
    local ENVIRONMENT=$1
    local ENV_ACCOUNT_ID
    local ENV_REGION
    local ENV_STATE_BUCKET
    local ENV_ROLE_NAME

    ENV_ACCOUNT_ID=$(get_environment_config_value "$ENVIRONMENT" "account_id")
    ENV_REGION=$(get_environment_config_value "$ENVIRONMENT" "region")
    ENV_STATE_BUCKET=$(get_environment_config_value "$ENVIRONMENT" "state_bucket")
    ENV_ROLE_NAME=$(get_environment_config_value "$ENVIRONMENT" "role_name")

    if [[ -z "$ENV_ACCOUNT_ID" || -z "$ENV_REGION" || -z "$ENV_STATE_BUCKET" || -z "$ENV_ROLE_NAME" ]]; then
        ENV_ACCOUNT_ID="$ACCOUNT_ID"
        ENV_REGION="$DETECTED_REGION"
        ENV_STATE_BUCKET="$TF_STATE_BUCKET"
        ENV_ROLE_NAME="$DEFAULT_ROLE_NAME"

        upsert_environment_config "$ENVIRONMENT" "$ENV_ACCOUNT_ID" "$ENV_REGION" "$ENV_STATE_BUCKET" "$ENV_ROLE_NAME"
    fi

    if [[ "$ENV_ACCOUNT_ID" != "$ACCOUNT_ID" ]]; then
        error "Environment '$ENVIRONMENT' is mapped to account '$ENV_ACCOUNT_ID' but current AWS account is '$ACCOUNT_ID'. Switch credentials or update $ENV_CONFIG_FILE."
    fi

    echo "$ENV_ACCOUNT_ID|$ENV_REGION|$ENV_STATE_BUCKET|$ENV_ROLE_NAME"
}

# Function to provision a single environment
provision_environment() {
    local ENVIRONMENT=$1
    local ENV_MAPPING
    local ENV_ACCOUNT_ID
    local ENV_REGION
    local ENV_STATE_BUCKET
    local ENV_ROLE_NAME

    echo ""
    info "========================================="
    info "Provisioning environment: $ENVIRONMENT"
    info "========================================="

    ENV_MAPPING=$(resolve_environment_mapping "$ENVIRONMENT")
    IFS='|' read -r ENV_ACCOUNT_ID ENV_REGION ENV_STATE_BUCKET ENV_ROLE_NAME <<< "$ENV_MAPPING"

    info "Mapping for '$ENVIRONMENT': account=$ENV_ACCOUNT_ID region=$ENV_REGION state_bucket=$ENV_STATE_BUCKET role=$ENV_ROLE_NAME"

    # Create environment directory structure
    ENV_DIR="$REPO_ROOT/environments/$ENVIRONMENT"
    info "Creating environment directory: $ENV_DIR"
    mkdir -p "$ENV_DIR"

    # Create backend.tf
    info "Creating backend.tf..."
    cat > "$ENV_DIR/backend.tf" << EOF
terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket       = "${ENV_STATE_BUCKET}"
    key          = "environments/${ENVIRONMENT}/terraform.tfstate"
    region       = "${ENV_REGION}"
    encrypt      = true
    use_lockfile = true
  }
}
EOF
    success "Created backend.tf"

    # Create terraform.tfvars
    info "Creating terraform.tfvars..."
    cat > "$ENV_DIR/terraform.tfvars" << EOF
# GitHub repository for OIDC provider
github_repo = "$GITHUB_REPO"

# OIDC provider is managed in bootstrap/account and consumed by environment stacks
use_existing_oidc_provider = true

# IAM role name for GitHub Actions
role_name = "${ENV_ROLE_NAME}"

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
  default     = "${ENV_REGION}"
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
  default     = "${ENV_ROLE_NAME}"
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
  EXPECTED_AWS_ACCOUNT_ID: '${ENV_ACCOUNT_ID}'
  AWS_REGION: '${ENV_REGION}'
  GITHUB_ACTIONS_ROLE_NAME: '${ENV_ROLE_NAME}'
  ENVIRONMENT: ${ENVIRONMENT}
  TF_WORKING_DIR: environments/${ENVIRONMENT}
  TF_STATE_BUCKET: '${ENV_STATE_BUCKET}'

jobs:
  tflint:
    name: TFLint Scan
    uses: ./.github/workflows/tflint-scan.yml

  checkov:
    name: Checkov Security Scan
    uses: ./.github/workflows/checkov-scan.yml
    with:
      working_directory: 'environments/${ENVIRONMENT}'
      soft_fail: false

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
          role-to-assume: arn:aws:iam::\${{ env.EXPECTED_AWS_ACCOUNT_ID }}:role/\${{ env.GITHUB_ACTIONS_ROLE_NAME }}
          aws-region: \${{ env.AWS_REGION }}
          role-session-name: GitHubActions-Terraform-Plan-${ENV_CAPITALIZED}

      - name: Validate assumed account mapping
        run: |
          ACTUAL_ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
          if [[ "$ACTUAL_ACCOUNT_ID" != "${ENV_ACCOUNT_ID}" ]]; then
            echo "Expected account ${ENV_ACCOUNT_ID}, but assumed $ACTUAL_ACCOUNT_ID."
            exit 1
          fi

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3

      - name: Terraform Init
        run: |
          terraform init \\
            -backend-config="bucket=\${{ env.TF_STATE_BUCKET }}" \\
            -backend-config="key=environments/${ENVIRONMENT}/terraform.tfstate" \\
            -backend-config="region=\${{ env.AWS_REGION }}"

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
      aws-region: ${ENV_REGION}
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
          role-to-assume: arn:aws:iam::\${{ env.EXPECTED_AWS_ACCOUNT_ID }}:role/\${{ env.GITHUB_ACTIONS_ROLE_NAME }}
          aws-region: \${{ env.AWS_REGION }}
          role-session-name: GitHubActions-Terraform-Apply-${ENV_CAPITALIZED}

      - name: Validate assumed account mapping
        run: |
          ACTUAL_ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
          if [[ "$ACTUAL_ACCOUNT_ID" != "${ENV_ACCOUNT_ID}" ]]; then
            echo "Expected account ${ENV_ACCOUNT_ID}, but assumed $ACTUAL_ACCOUNT_ID."
            exit 1
          fi

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3

      - name: Terraform Init
        run: |
          terraform init \\
            -backend-config="bucket=\${{ env.TF_STATE_BUCKET }}" \\
            -backend-config="key=environments/${ENVIRONMENT}/terraform.tfstate" \\
            -backend-config="region=\${{ env.AWS_REGION }}"

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

provision_bootstrap_identity_stack

# Provision each environment
for ENV in "${ENVIRONMENTS[@]}"; do
    provision_environment "$ENV"
done

#######################################
# Step 4: Deploy Bootstrap + Environments
#######################################
section "Step 4/4: Deploy Bootstrap + Environments"

if [[ "$SKIP_DEPLOY" == true ]]; then
    warning "Skipping deployment (files created only)"
else
    BOOTSTRAP_DIR="$REPO_ROOT/bootstrap/account"
    for ENV in "${ENVIRONMENTS[@]}"; do
        resolve_environment_mapping "$ENV" > /dev/null
    done

    echo ""
    info "========================================="
    info "Deploying bootstrap stack: account"
    info "========================================="

    cd "$BOOTSTRAP_DIR"

    info "Initializing Terraform..."
    terraform init
    success "Terraform initialized"

    info "Validating Terraform configuration..."
    terraform validate
    success "Configuration is valid"

    info "Creating deployment plan..."
    BOOTSTRAP_PLAN_OUTPUT=$(terraform plan -out=tfplan -var-file=terraform.tfvars 2>&1 || true)

    if echo "$BOOTSTRAP_PLAN_OUTPUT" | grep -q "No changes"; then
        success "No changes detected for bootstrap/account."
        rm -f tfplan
    else
        echo "$BOOTSTRAP_PLAN_OUTPUT"

        if [[ "$AUTO_APPROVE" == false ]]; then
            echo ""
            warning "Review the bootstrap plan above carefully."
            read -r -p "Apply bootstrap/account changes? [y/N] " CONFIRM

            if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
                info "Bootstrap deployment cancelled."
                rm -f tfplan
                exit 0
            fi
        fi

        info "Applying Terraform changes for bootstrap/account..."
        if terraform apply -auto-approve tfplan; then
            success "Bootstrap stack deployed successfully!"

            info "Verifying bootstrap state was saved to S3..."
            sleep 2

            if aws s3api head-object \
                --bucket "$TF_STATE_BUCKET" \
                --key "bootstrap/account/terraform.tfstate" \
                --region "$AWS_REGION" &>/dev/null; then
                success "Bootstrap state file confirmed in S3"
            else
                error "Bootstrap state file not found in S3!"
            fi
        else
            error "Terraform apply failed for bootstrap/account!"
        fi

        rm -f tfplan
    fi

    for ENV in "${ENVIRONMENTS[@]}"; do
        echo ""
        info "========================================="
        info "Deploying environment stack: $ENV"
        info "========================================="

        ENV_MAPPING=$(resolve_environment_mapping "$ENV")
        IFS='|' read -r ENV_ACCOUNT_ID ENV_REGION ENV_STATE_BUCKET ENV_ROLE_NAME <<< "$ENV_MAPPING"

        ENV_DIR="$REPO_ROOT/environments/$ENV"
        cd "$ENV_DIR"

        info "Initializing Terraform..."
        terraform init
        success "Terraform initialized"

        info "Validating Terraform configuration..."
        terraform validate
        success "Configuration is valid"

        info "Creating deployment plan..."
        PLAN_OUTPUT=$(terraform plan -out=tfplan -var-file=terraform.tfvars 2>&1 || true)

        if echo "$PLAN_OUTPUT" | grep -q "No changes"; then
            success "No changes detected for $ENV. Infrastructure is up to date."
            rm -f tfplan
            continue
        fi

        echo "$PLAN_OUTPUT"

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

        info "Applying Terraform changes for $ENV..."
        if terraform apply -auto-approve tfplan; then
            success "Environment deployed successfully for $ENV!"

            info "Verifying state was saved to S3..."
            sleep 2

            if aws s3api head-object \
                --bucket "$ENV_STATE_BUCKET" \
                --key "environments/$ENV/terraform.tfstate" \
                --region "$ENV_REGION" &>/dev/null; then
                success "State file confirmed in S3"
            else
                error "State file not found in S3! Apply may have failed to save state."
            fi

            echo ""
            info "Terraform Outputs for $ENV:"
            echo -e "${GREEN}"
            terraform output
            echo -e "${NC}"
        else
            error "Terraform apply failed for $ENV!"
        fi

        rm -f tfplan
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
echo "  ✅ S3 Native State Locking (.tflock files)"
echo "  ✅ Account bootstrap stack: bootstrap/account/"
echo "  ✅ Shared GitHub OIDC provider in AWS (bootstrap-owned)"
echo "  ✅ Environment mapping file: config/environments.json"
echo ""

for ENV in "${ENVIRONMENTS[@]}"; do
    ENV_MAPPING=$(resolve_environment_mapping "$ENV")
    IFS='|' read -r ENV_ACCOUNT_ID ENV_REGION ENV_STATE_BUCKET ENV_ROLE_NAME <<< "$ENV_MAPPING"

    echo "  ✅ Environment: $ENV"
    echo "     - Terraform files in environments/$ENV/"
    echo "     - Account mapping: $ENV_ACCOUNT_ID ($ENV_REGION)"
    echo "     - State bucket: $ENV_STATE_BUCKET"
    echo "     - Role name: $ENV_ROLE_NAME"
    echo "     - GitHub workflow: .github/workflows/terraform-deploy-${ENV}.yml"
done

echo ""
info "Next Steps:"
echo ""
echo "1. Review generated files:"
echo "   - bootstrap/account/"
echo "   - config/environments.json"
for ENV in "${ENVIRONMENTS[@]}"; do
    echo "   - environments/${ENV}/terraform.tfvars"
done
echo ""
echo "2. Commit the mapping and generated Terraform files:"
echo "   git add ."
echo "   git commit -m 'Initial setup: Add infrastructure configuration'"
echo "   git push origin main"
echo ""
echo "3. (Optional) Configure GitHub Environment Protection:"
for ENV in "${ENVIRONMENTS[@]}"; do
    echo "   - Go to Settings → Environments → ${ENV}"
    echo "   - Add required reviewers for ${ENV} deployments"
done
echo ""
echo "4. Test with a pull request to trigger the CI/CD pipeline"
echo ""

success "Your AWS Terraform Starter Kit is ready! 🚀"
echo ""
