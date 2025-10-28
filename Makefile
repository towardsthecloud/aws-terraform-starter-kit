.PHONY: help setup install-tools validate-full validate-env lint security-scan init plan apply destroy validate format check cleanup

# Default target
help:
	@echo "════════════════════════════════════════════════════════════"
	@echo "  Terraform AWS Starter Kit - Makefile"
	@echo "════════════════════════════════════════════════════════════"
	@echo ""
	@echo "Setup Commands:"
	@echo "  setup         - Complete setup wizard (bootstrap + provision + OIDC)"
	@echo "  install-tools - Install required development tools"
	@echo ""
	@echo "Validation Commands:"
	@echo "  validate-full - Run all validation checks (fmt, validate, lint, security)"
	@echo "  validate-env  - Run terraform validate for specific environment (ENV=<env>)"
	@echo "  lint          - Run TFLint checks"
	@echo "  security-scan - Run Checkov security scan"
	@echo "  format        - Format Terraform files"
	@echo ""
	@echo "Deployment Commands (require ENV=<environment>):"
	@echo "  init          - Initialize Terraform (ENV=<env>)"
	@echo "  plan          - Create Terraform plan (ENV=<env>)"
	@echo "  apply         - Apply Terraform changes (ENV=<env>)"
	@echo "  destroy       - Destroy Terraform resources (ENV=<env>)"
	@echo ""
	@echo "Utility Commands:"
	@echo "  cleanup       - Interactive cleanup script"
	@echo "  check         - Check tool versions"
	@echo ""
	@echo "Examples:"
	@echo "  make install-tools                  # Install dev tools"
	@echo "  make setup                          # Interactive wizard"
	@echo "  make validate-full                  # Validate all environments"
	@echo "  make init ENV=production"
	@echo "  make init ENV=production ARGS=\"-upgrade\""
	@echo "  make plan ENV=production"
	@echo "  make plan ENV=production ARGS=\"-out=tfplan\""
	@echo "  make apply ENV=production ARGS=\"-auto-approve\""
	@echo ""

# Complete setup wizard
setup:
	@./scripts/setup.sh

# Install required tools
install-tools:
	@echo "════════════════════════════════════════════════════════════"
	@echo "  Installing Development Tools"
	@echo "════════════════════════════════════════════════════════════"
	@echo ""
	@OS="$$(uname -s)"; \
	echo "Detected OS: $$OS"; \
	echo ""; \
	\
	echo "📦 Installing Terraform..."; \
	if command -v terraform >/dev/null 2>&1; then \
		echo "✅ Terraform already installed: $$(terraform version | head -n1)"; \
	else \
		case "$$OS" in \
			Darwin*) \
				if command -v brew >/dev/null 2>&1; then \
					brew tap hashicorp/tap && brew install hashicorp/tap/terraform; \
				else \
					echo "❌ Homebrew not found. Please install from https://www.terraform.io/downloads"; \
				fi ;; \
			Linux*) \
				echo "Please install Terraform from https://www.terraform.io/downloads"; ;; \
			*) \
				echo "❌ Unsupported OS. Please install manually."; ;; \
		esac; \
	fi; \
	echo ""; \
	\
	echo "📦 Installing AWS CLI..."; \
	if command -v aws >/dev/null 2>&1; then \
		echo "✅ AWS CLI already installed: $$(aws --version)"; \
	else \
		case "$$OS" in \
			Darwin*) \
				if command -v brew >/dev/null 2>&1; then \
					brew install awscli; \
				else \
					echo "❌ Homebrew not found. Please install from https://aws.amazon.com/cli/"; \
				fi ;; \
			Linux*) \
				echo "Installing AWS CLI v2..."; \
				curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && \
				unzip awscliv2.zip && \
				sudo ./aws/install && \
				rm -rf aws awscliv2.zip; ;; \
			*) \
				echo "❌ Unsupported OS. Please install manually."; ;; \
		esac; \
	fi; \
	echo ""; \
	\
	echo "📦 Installing TFLint..."; \
	if command -v tflint >/dev/null 2>&1; then \
		echo "✅ TFLint already installed: $$(tflint --version | head -n1)"; \
	else \
		case "$$OS" in \
			Darwin*) \
				if command -v brew >/dev/null 2>&1; then \
					brew install tflint; \
				else \
					curl -s https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash; \
				fi ;; \
			Linux*) \
				curl -s https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash; ;; \
			*) \
				echo "❌ Unsupported OS. Please install manually."; ;; \
		esac; \
	fi; \
	echo ""; \
	\
	echo "📦 Installing Checkov..."; \
	if command -v checkov >/dev/null 2>&1; then \
		echo "✅ Checkov already installed: $$(checkov --version | head -n1)"; \
	else \
		if command -v pip3 >/dev/null 2>&1; then \
			pip3 install checkov; \
		elif command -v pip >/dev/null 2>&1; then \
			pip install checkov; \
		elif command -v brew >/dev/null 2>&1 && [ "$$OS" = "Darwin" ]; then \
			brew install checkov; \
		else \
			echo "⚠️  pip/pip3 not found. Please install Checkov manually."; \
			echo "   Visit: https://www.checkov.io/2.Basics/Installing%20Checkov.html"; \
		fi; \
	fi; \
	echo ""; \
	\
	echo "📦 Installing Granted..."; \
	if command -v assume >/dev/null 2>&1; then \
		echo "✅ Granted already installed"; \
	else \
		case "$$OS" in \
			Darwin*) \
				if command -v brew >/dev/null 2>&1; then \
					brew tap common-fate/granted && brew install granted; \
				else \
					echo "⚠️  Homebrew not found. Please install Granted manually."; \
					echo "   Visit: https://docs.commonfate.io/granted/getting-started"; \
				fi ;; \
			Linux*) \
				curl -OL https://releases.commonfate.io/granted/v0.20.3/granted_0.20.3_linux_x86_64.tar.gz && \
				sudo tar -zxvf granted_*.tar.gz -C /usr/local/bin/ && \
				rm granted_*.tar.gz; ;; \
			*) \
				echo "❌ Unsupported OS. Please install manually."; ;; \
		esac; \
	fi; \
	echo ""; \
	\
	echo "════════════════════════════════════════════════════════════"; \
	echo "✅ Tool installation complete!"; \
	echo ""; \
	echo "Run 'make check' to verify all installations."; \
	echo "════════════════════════════════════════════════════════════"

# Validate all environments (comprehensive)
validate-full:
	@echo "════════════════════════════════════════════════════════════"
	@echo "  Running Full Terraform Validation"
	@echo "════════════════════════════════════════════════════════════"
	@echo ""
	@echo "🔍 Step 1/4: Checking Terraform formatting..."
	@if terraform fmt -check -recursive; then \
		echo "✅ All Terraform files are properly formatted"; \
	else \
		echo "❌ Some files need formatting. Run 'terraform fmt -recursive' to fix."; \
		exit 1; \
	fi
	@echo ""
	@echo "🔍 Step 2/4: Validating Terraform configurations..."
	@VALIDATION_SUCCESS=true; \
	for env_dir in environments/*/; do \
		if [ -d "$$env_dir" ]; then \
			env_name=$$(basename "$$env_dir"); \
			echo "  Validating environment: $$env_name"; \
			cd "$$env_dir" && \
			if terraform init -backend=false >/dev/null 2>&1; then \
				if terraform validate >/dev/null 2>&1; then \
					echo "  ✅ Environment '$$env_name' is valid"; \
				else \
					echo "  ❌ Environment '$$env_name' validation failed"; \
					terraform validate; \
					VALIDATION_SUCCESS=false; \
				fi; \
			else \
				echo "  ⚠️  Could not initialize '$$env_name' (skipping validation)"; \
			fi; \
			cd - >/dev/null; \
		fi; \
	done; \
	if [ "$$VALIDATION_SUCCESS" = "false" ]; then \
		exit 1; \
	fi
	@echo ""
	@echo "🔍 Step 3/4: Running TFLint..."
	@if ! command -v tflint >/dev/null 2>&1; then \
		echo "⚠️  TFLint not installed. Run 'make install-tools' to install."; \
		exit 1; \
	fi
	@if [ -f ".tflint.hcl" ]; then \
		tflint --init >/dev/null && \
		if tflint --recursive --format compact; then \
			echo "✅ TFLint checks passed"; \
		else \
			echo "❌ TFLint found issues"; \
			exit 1; \
		fi; \
	else \
		echo "⚠️  No .tflint.hcl found, skipping TFLint"; \
	fi
	@echo ""
	@echo "🔍 Step 4/4: Running Checkov security scan..."
	@if ! command -v checkov >/dev/null 2>&1; then \
		echo "⚠️  Checkov not installed. Run 'make install-tools' to install."; \
		exit 1; \
	fi
	@if [ -f ".checkov.yml" ]; then \
		if checkov -d . --config-file .checkov.yml --compact --quiet; then \
			echo "✅ Checkov security scan passed"; \
		else \
			echo "❌ Checkov found security issues"; \
			exit 1; \
		fi; \
	else \
		if checkov -d . --compact --quiet; then \
			echo "✅ Checkov security scan passed"; \
		else \
			echo "❌ Checkov found security issues"; \
			exit 1; \
		fi; \
	fi
	@echo ""
	@echo "════════════════════════════════════════════════════════════"
	@echo "✅ All validation checks passed successfully!"
	@echo "════════════════════════════════════════════════════════════"

# Lint with TFLint
lint:
	@echo "Running TFLint..."
	@if command -v tflint >/dev/null 2>&1; then \
		tflint --init && tflint --recursive --format compact; \
	else \
		echo "TFLint not installed. Run 'make validate-all' to install."; \
		exit 1; \
	fi

# Security scan with Checkov
security-scan:
	@echo "Running Checkov security scan..."
	@if command -v checkov >/dev/null 2>&1; then \
		checkov -d . --config-file .checkov.yml; \
	else \
		echo "Checkov not installed. Install with: pip install checkov"; \
		exit 1; \
	fi

# Initialize Terraform
init:
	@if [ -z "$(ENV)" ]; then \
		echo "❌ Error: ENV variable is required"; \
		echo "Usage: make init ENV=production"; \
		echo "       make init ENV=production ARGS=\"-upgrade\""; \
		exit 1; \
	fi
	@if [ ! -d "environments/$(ENV)" ]; then \
		echo "❌ Error: Environment '$(ENV)' does not exist"; \
		echo "Available environments:"; \
		ls -1 environments/ 2>/dev/null || echo "  (none)"; \
		exit 1; \
	fi
	cd environments/$(ENV) && terraform init $(ARGS)

# Validate specific environment
validate-env:
	@if [ -z "$(ENV)" ]; then \
		echo "❌ Error: ENV variable is required"; \
		echo "Usage: make validate-env ENV=production"; \
		echo "       make validate-env ENV=production ARGS=\"-json\""; \
		exit 1; \
	fi
	@if [ ! -d "environments/$(ENV)" ]; then \
		echo "❌ Error: Environment '$(ENV)' does not exist"; \
		exit 1; \
	fi
	cd environments/$(ENV) && terraform validate $(ARGS)

# Format Terraform files
format:
	terraform fmt -recursive

# Create Terraform plan
plan:
	@if [ -z "$(ENV)" ]; then \
		echo "❌ Error: ENV variable is required"; \
		echo "Usage: make plan ENV=production"; \
		echo "       make plan ENV=production ARGS=\"-out=tfplan\""; \
		exit 1; \
	fi
	@if [ ! -d "environments/$(ENV)" ]; then \
		echo "❌ Error: Environment '$(ENV)' does not exist"; \
		exit 1; \
	fi
	cd environments/$(ENV) && terraform plan $(ARGS)

# Apply Terraform changes
apply:
	@if [ -z "$(ENV)" ]; then \
		echo "❌ Error: ENV variable is required"; \
		echo "Usage: make apply ENV=production"; \
		echo "       make apply ENV=production ARGS=\"-auto-approve\""; \
		exit 1; \
	fi
	@if [ ! -d "environments/$(ENV)" ]; then \
		echo "❌ Error: Environment '$(ENV)' does not exist"; \
		exit 1; \
	fi
	cd environments/$(ENV) && terraform apply $(ARGS)

# Destroy Terraform resources
destroy:
	@if [ -z "$(ENV)" ]; then \
		echo "❌ Error: ENV variable is required"; \
		echo "Usage: make destroy ENV=production"; \
		echo "       make destroy ENV=production ARGS=\"-auto-approve\""; \
		exit 1; \
	fi
	@if [ ! -d "environments/$(ENV)" ]; then \
		echo "❌ Error: Environment '$(ENV)' does not exist"; \
		exit 1; \
	fi
	cd environments/$(ENV) && terraform destroy $(ARGS)

# Cleanup script
cleanup:
	@./scripts/cleanup.sh

# Check Terraform and AWS CLI versions
check:
	@echo "════════════════════════════════════════════════════════════"
	@echo "  Checking required tools..."
	@echo "════════════════════════════════════════════════════════════"
	@echo ""
	@echo "Terraform:"
	@if command -v terraform >/dev/null 2>&1; then terraform version; else echo "❌ Terraform not installed"; fi
	@echo ""
	@echo "AWS CLI:"
	@if command -v aws >/dev/null 2>&1; then aws --version; else echo "❌ AWS CLI not installed"; fi
	@echo ""
	@echo "TFLint:"
	@if command -v tflint >/dev/null 2>&1; then tflint --version; else echo "⚠️  TFLint not installed (optional)"; fi
	@echo ""
	@echo "Checkov:"
	@if command -v checkov >/dev/null 2>&1; then checkov --version; else echo "⚠️  Checkov not installed (optional)"; fi
	@echo ""
	@echo "Granted:"
	@if command -v assume >/dev/null 2>&1; then assume --version 2>&1 || echo "assume installed"; else echo "⚠️  Granted not installed (optional)"; fi
	@echo ""
	@echo "════════════════════════════════════════════════════════════"
