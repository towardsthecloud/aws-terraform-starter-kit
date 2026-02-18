#!/usr/bin/env bash

# AWS Terraform Starter Kit - Cleanup Script
# This script helps clean up resources and local files

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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
}

echo -e "${BLUE}"
cat << "EOF"
╔════════════════════════════════════════════════════════════╗
║        AWS Terraform Starter Kit - Cleanup Script         ║
╚════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Get repository root
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Function to destroy resources in an environment
destroy_environment_resources() {
    local env_name=$1
    local env_dir="$REPO_ROOT/environments/$env_name"

    if [[ ! -d "$env_dir" ]]; then
        warning "Environment directory not found: $env_dir"
        return 1
    fi

    info "Destroying resources for environment: $env_name"
    cd "$env_dir"

    # Check if this environment manages the OIDC provider
    local manages_oidc=false
    if [[ -f terraform.tfvars ]]; then
        if grep -q "use_existing_oidc_provider.*=.*false" terraform.tfvars 2>/dev/null; then
            manages_oidc=true
            warning "This environment manages the OIDC provider!"
            warning "Destroying this environment will DELETE the OIDC provider."
            warning "Other environments may be using this OIDC provider."
            echo ""
        fi
    fi

    if [[ -f terraform.tfstate || -f .terraform/terraform.tfstate ]]; then
        terraform init -upgrade 2>/dev/null || true
        terraform plan -destroy
        echo ""

        if [[ "$manages_oidc" == true ]]; then
            warning "⚠️  CRITICAL: This will destroy the shared OIDC provider!"
            read -r -p "Type 'yes' to confirm destruction of OIDC provider and all resources: " CONFIRM
            # Trim whitespace and convert to lowercase
            CONFIRM=$(echo "$CONFIRM" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
            if [[ "$CONFIRM" != "yes" ]]; then
                warning "Destruction cancelled for $env_name"
                return 1
            fi
        else
            read -r -p "Do you want to destroy these resources? (y/N): " CONFIRM
            if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
                warning "Destruction cancelled for $env_name"
                return 1
            fi
        fi

        terraform destroy -auto-approve
        success "Resources destroyed for $env_name"
    else
        info "No state file found for $env_name. No resources to destroy."
    fi

    cd "$REPO_ROOT"
}

# Function to destroy all environment resources
destroy_all_environments() {
    warning "This will destroy resources in ALL environments!"
    echo ""

    local environments=()

    for env_dir in "$REPO_ROOT"/environments/*/; do
        if [[ -d "$env_dir" ]]; then
            local env_name=$(basename "$env_dir")
            environments+=("$env_name")
        fi
    done

    if [[ ${#environments[@]} -eq 0 ]]; then
        info "No environments found."
        return 0
    fi

    info "Found environments: ${environments[*]}"

    echo ""
    read -r -p "Proceed with destroying all environments? (y/N): " CONFIRM

    if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
        warning "Cancelled by user"
        return 1
    fi

    for env in "${environments[@]}"; do
        echo ""
        destroy_environment_resources "$env"
    done
}

# Function to destroy account bootstrap identity resources
destroy_bootstrap_identity_resources() {
    local bootstrap_dir="$REPO_ROOT/bootstrap/account"

    if [[ ! -d "$bootstrap_dir" ]]; then
        info "No bootstrap/account directory found. Skipping bootstrap identity cleanup."
        return 0
    fi

    if [[ ! -f "$bootstrap_dir/main.tf" ]]; then
        warning "bootstrap/account exists but no Terraform configuration found. Skipping."
        return 0
    fi

    info "Destroying bootstrap identity resources from: bootstrap/account"
    cd "$bootstrap_dir"

    terraform init -upgrade 2>/dev/null || true
    terraform plan -destroy
    echo ""

    read -r -p "Destroy bootstrap identity resources (OIDC provider)? (yes/N): " CONFIRM
    CONFIRM=$(echo "$CONFIRM" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')

    if [[ "$CONFIRM" != "yes" ]]; then
        warning "Bootstrap identity cleanup cancelled"
        cd "$REPO_ROOT"
        return 1
    fi

    terraform destroy -auto-approve
    success "Bootstrap identity resources destroyed"
    cd "$REPO_ROOT"
}

# Function to destroy bootstrap resources (OIDC + S3 backend)
destroy_bootstrap_resources() {
    warning "This will destroy bootstrap identity resources and the Terraform state backend!"
    warning "Bootstrap identity resources include the shared GitHub OIDC provider."
    warning "Make sure all environments are destroyed first, or you'll lose state!"
    echo ""

    # Load backend configuration
    local backend_config="$REPO_ROOT/.terraform-backend.conf"
    if [[ ! -f "$backend_config" ]]; then
        error "Backend configuration not found: $backend_config"
        info "If you've already deleted it, you'll need to manually specify the resources."
        return 1
    fi

    # shellcheck disable=SC1090
    source "$backend_config"

    info "Backend resources to delete:"
    echo "  S3 Bucket: ${TF_STATE_BUCKET}"
    echo "  Region: ${AWS_REGION}"
    echo ""

    read -r -p "Are you absolutely sure you want to delete these resources? (yes/N): " CONFIRM

    # Trim whitespace and convert to lowercase
    CONFIRM=$(echo "$CONFIRM" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')

    if [[ "$CONFIRM" != "yes" ]]; then
        warning "Bootstrap resource deletion cancelled"
        return 1
    fi

    # Verify AWS credentials
    if ! aws sts get-caller-identity > /dev/null 2>&1; then
        error "AWS credentials not configured. Please configure AWS CLI or use Granted (assume)."
        return 1
    fi

    if ! destroy_bootstrap_identity_resources; then
        warning "Skipping backend deletion because bootstrap identity cleanup was cancelled or failed."
        return 1
    fi

    # Delete S3 bucket (must empty it first)
    if aws s3api head-bucket --bucket "$TF_STATE_BUCKET" --region "$AWS_REGION" 2>/dev/null; then
        info "Emptying S3 bucket: $TF_STATE_BUCKET"

        # Delete all versions and delete markers
        aws s3api list-object-versions \
            --bucket "$TF_STATE_BUCKET" \
            --region "$AWS_REGION" \
            --output json \
            --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' | \
        jq -r '.Objects[] | "\(.Key) \(.VersionId)"' | \
        while read -r key version; do
            aws s3api delete-object \
                --bucket "$TF_STATE_BUCKET" \
                --key "$key" \
                --version-id "$version" \
                --region "$AWS_REGION" > /dev/null
        done 2>/dev/null || true

        # Delete delete markers
        aws s3api list-object-versions \
            --bucket "$TF_STATE_BUCKET" \
            --region "$AWS_REGION" \
            --output json \
            --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' | \
        jq -r '.Objects[] | "\(.Key) \(.VersionId)"' | \
        while read -r key version; do
            aws s3api delete-object \
                --bucket "$TF_STATE_BUCKET" \
                --key "$key" \
                --version-id "$version" \
                --region "$AWS_REGION" > /dev/null
        done 2>/dev/null || true

        info "Deleting S3 bucket: $TF_STATE_BUCKET"
        if aws s3api delete-bucket --bucket "$TF_STATE_BUCKET" --region "$AWS_REGION"; then
            success "S3 bucket deleted: $TF_STATE_BUCKET"
        else
            error "Failed to delete S3 bucket. It may not be empty or may not exist."
        fi
    else
        warning "S3 bucket not found: $TF_STATE_BUCKET"
    fi

    # Remove backend configuration file
    if [[ -f "$backend_config" ]]; then
        rm -f "$backend_config"
        success "Removed backend configuration file"
    fi

    success "Bootstrap resources cleanup completed (identity + backend)"
}

# Function to clean local files
clean_local() {
    info "Cleaning local Terraform files in all environments..."

    local cleaned=0
    for env_dir in "$REPO_ROOT"/environments/*/; do
        if [[ -d "$env_dir" ]]; then
            local env_name=$(basename "$env_dir")
            cd "$env_dir"

            # Remove Terraform files
            if [[ -d .terraform ]]; then
                rm -rf .terraform/
                info "Removed .terraform directory for $env_name"
                ((cleaned++))
            fi

            if [[ -f .terraform.lock.hcl ]]; then
                rm -f .terraform.lock.hcl
                info "Removed .terraform.lock.hcl for $env_name"
            fi

            if [[ -f terraform.tfstate.backup ]]; then
                rm -f terraform.tfstate.backup
                info "Removed terraform.tfstate.backup for $env_name"
            fi

            if [[ -f tfplan ]]; then
                rm -f tfplan
                info "Removed tfplan for $env_name"
            fi
        fi
    done

    # Clean root level files
    cd "$REPO_ROOT"
    if [[ -d bootstrap/account/.terraform ]]; then
        rm -rf bootstrap/account/.terraform
        info "Removed bootstrap/account/.terraform directory"
    fi

    if [[ -f bootstrap/account/.terraform.lock.hcl ]]; then
        rm -f bootstrap/account/.terraform.lock.hcl
        info "Removed bootstrap/account/.terraform.lock.hcl"
    fi

    if [[ -f bootstrap/account/tfplan ]]; then
        rm -f bootstrap/account/tfplan
        info "Removed bootstrap/account/tfplan"
    fi

    if [[ -f .terraform-backend.conf ]]; then
        rm -f .terraform-backend.conf
        info "Removed .terraform-backend.conf"
    fi

    if [[ $cleaned -gt 0 ]]; then
        success "Local cleanup completed for $cleaned environment(s)"
    else
        info "No local files to clean"
    fi
}

# Function to remove environment and workflow source files
remove_source_files() {
    warning "This will DELETE environment directories, bootstrap stack files, and workflow files!"
    warning "These are source files that may be committed to Git."
    echo ""

    info "Files that will be deleted:"
    echo ""

    # List environments
    local env_count=0
    if [[ -d "$REPO_ROOT/environments" ]]; then
        for env_dir in "$REPO_ROOT"/environments/*/; do
            # Check if pattern matched actual directories (not the glob pattern itself)
            if [[ -d "$env_dir" && "$env_dir" != "$REPO_ROOT/environments/*/" ]]; then
                local env_name=$(basename "$env_dir")
                echo "  - environments/$env_name/"
                ((env_count++))
            fi
        done
    fi

    # List workflows
    local workflow_count=0
    if [[ -d "$REPO_ROOT/.github/workflows" ]]; then
        for workflow_file in "$REPO_ROOT"/.github/workflows/terraform-deploy-*.yml; do
            # Check if pattern matched actual files (not the glob pattern itself)
            if [[ -f "$workflow_file" && "$workflow_file" != "$REPO_ROOT/.github/workflows/terraform-deploy-*.yml" ]]; then
                local workflow_name=$(basename "$workflow_file")
                echo "  - .github/workflows/$workflow_name"
                ((workflow_count++))
            fi
        done
    fi

    local bootstrap_count=0
    if [[ -d "$REPO_ROOT/bootstrap/account" ]]; then
        echo "  - bootstrap/account/"
        bootstrap_count=1
    fi

    local mapping_count=0
    if [[ -f "$REPO_ROOT/config/environments.json" ]]; then
        echo "  - config/environments.json"
        mapping_count=1
    fi

    if [[ $env_count -eq 0 && $workflow_count -eq 0 && $bootstrap_count -eq 0 && $mapping_count -eq 0 ]]; then
        info "No source files to remove"
        return 0
    fi

    echo ""
    warning "Total: $env_count environment(s), $workflow_count workflow(s), $bootstrap_count bootstrap stack(s), $mapping_count mapping file(s)"
    echo ""
    read -r -p "Are you absolutely sure you want to delete these source files? (yes/N): " CONFIRM

    # Trim whitespace and convert to lowercase for comparison
    CONFIRM=$(echo "$CONFIRM" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')

    if [[ "$CONFIRM" != "yes" ]]; then
        warning "Source file removal cancelled"
        return 1
    fi

    # Remove environment directories
    if [[ $env_count -gt 0 ]]; then
        info "Removing environment directories..."
        for env_dir in "$REPO_ROOT"/environments/*/; do
            # Check if pattern matched actual directories (not the glob pattern itself)
            if [[ -d "$env_dir" && "$env_dir" != "$REPO_ROOT/environments/*/" ]]; then
                local env_name=$(basename "$env_dir")
                rm -rf "$env_dir"
                success "Removed environments/$env_name/"
            fi
        done

        # Remove environments directory if empty
        if [[ -d "$REPO_ROOT/environments" ]] && [[ -z "$(ls -A "$REPO_ROOT/environments" 2>/dev/null)" ]]; then
            rmdir "$REPO_ROOT/environments"
            success "Removed empty environments/ directory"
        fi
    fi

    # Remove workflow files
    if [[ $workflow_count -gt 0 ]]; then
        info "Removing workflow files..."
        for workflow_file in "$REPO_ROOT"/.github/workflows/terraform-deploy-*.yml; do
            # Check if pattern matched actual files (not the glob pattern itself)
            if [[ -f "$workflow_file" && "$workflow_file" != "$REPO_ROOT/.github/workflows/terraform-deploy-*.yml" ]]; then
                local workflow_name=$(basename "$workflow_file")
                rm -f "$workflow_file"
                success "Removed .github/workflows/$workflow_name"
            fi
        done
    fi

    if [[ $bootstrap_count -gt 0 ]]; then
        rm -rf "$REPO_ROOT/bootstrap/account"
        success "Removed bootstrap/account/"
    fi

    if [[ -d "$REPO_ROOT/bootstrap" ]] && [[ -z "$(ls -A "$REPO_ROOT/bootstrap" 2>/dev/null)" ]]; then
        rmdir "$REPO_ROOT/bootstrap"
        success "Removed empty bootstrap/ directory"
    fi

    if [[ $mapping_count -gt 0 ]]; then
        rm -f "$REPO_ROOT/config/environments.json"
        success "Removed config/environments.json"
    fi

    if [[ -d "$REPO_ROOT/config" ]] && [[ -z "$(ls -A "$REPO_ROOT/config" 2>/dev/null)" ]]; then
        rmdir "$REPO_ROOT/config"
        success "Removed empty config/ directory"
    fi

    success "Source files removed"
}

# Main cleanup function
main() {
    info "Select cleanup option:"
    echo ""
    echo "  1. Destroy all environment resources (IAM roles, app resources, etc.)"
    echo "  2. Destroy bootstrap resources (shared OIDC + S3 backend)"
    echo "  3. Clean local files only (cached Terraform files)"
    echo "  4. Remove source files (environments + bootstrap + workflow + mapping)"
    echo "  5. Full cleanup (resources + bootstrap + local + source files)"
    echo "  6. Cancel"
    echo ""
    read -r -p "Enter your choice (1-6): " CHOICE
    echo ""

    case $CHOICE in
        1)
            destroy_all_environments
            ;;
        2)
            destroy_bootstrap_resources
            ;;
        3)
            clean_local
            ;;
        4)
            remove_source_files
            ;;
        5)
            warning "This will destroy EVERYTHING (AWS resources + source files)!"
            echo ""
            read -r -p "Are you absolutely sure? (yes/N): " CONFIRM
            # Trim whitespace and convert to lowercase
            CONFIRM=$(echo "$CONFIRM" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
            if [[ "$CONFIRM" == "yes" ]]; then
                destroy_all_environments
                echo ""
                destroy_bootstrap_resources
                echo ""
                clean_local
                echo ""
                remove_source_files
            else
                warning "Full cleanup cancelled"
                exit 0
            fi
            ;;
        6)
            info "Cleanup cancelled"
            exit 0
            ;;
        *)
            error "Invalid option"
            exit 1
            ;;
    esac

    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║              Cleanup Completed! 🎉                         ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
}

# Run main function
main "$@"
