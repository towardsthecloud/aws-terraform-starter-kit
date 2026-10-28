# Run `make help` to list the commands. Works with the GNU Make 3.81 that ships with macOS.

SHELL := /bin/bash
.DEFAULT_GOAL := help

# Environment to work on: a folder in environments/ (for example `make plan ENV=test`).
# Only set on the command line, because shells often export ENV for their startup file.
ENV :=
# Extra arguments for the Terraform command (for example ARGS="-out=tfplan").
ARGS :=

ENV_DIR := environments/$(ENV)
ENVIRONMENTS := $(notdir $(patsubst %/,%,$(wildcard environments/*/)))

.PHONY: help setup install-tools check format fmt-check validate validate-env validate-full lint security-scan require-env init plan apply destroy cleanup

help: ## Show this help
	@echo "Usage: make <command> [ENV=<environment>] [ARGS=\"<terraform arguments>\"]"
	@awk 'BEGIN {FS = ":.*## "} /^##@/ {printf "\n%s\n", substr($$0, 5)} /^[a-z-]+:.*## / {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo
	@echo "Environments: $(or $(ENVIRONMENTS),none yet (run make setup))"
	@echo
	@echo "Examples:"
	@echo "  make plan ENV=production ARGS=\"-out=tfplan\""
	@echo "  make apply ENV=production ARGS=\"tfplan\""

##@ Setup

setup: ## Run the setup wizard (state backend, OIDC role, environment, workflows)
	@./scripts/setup.sh

install-tools: ## Install Terraform, AWS CLI, jq, TFLint, Checkov, and Granted
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
	echo "📦 Installing jq..."; \
	if command -v jq >/dev/null 2>&1; then \
		echo "✅ jq already installed: $$(jq --version)"; \
	else \
		case "$$OS" in \
			Darwin*) \
				if command -v brew >/dev/null 2>&1; then \
					brew install jq; \
				else \
					echo "❌ Homebrew not found. Please install jq manually."; \
				fi ;; \
			Linux*) \
				if command -v apt-get >/dev/null 2>&1; then \
					sudo apt-get update && sudo apt-get install -y jq; \
				elif command -v yum >/dev/null 2>&1; then \
					sudo yum install -y jq; \
				else \
					echo "❌ No supported package manager found. Please install jq manually."; \
				fi ;; \
			*) \
				echo "❌ Unsupported OS. Please install jq manually."; ;; \
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
					brew install --cask terraform-linters/tap/tflint; \
				else \
					echo "❌ Homebrew not found. Please install from https://github.com/terraform-linters/tflint#installation"; \
				fi ;; \
			Linux*) \
				ARCH="$$(uname -m | sed 's/x86_64/amd64/; s/aarch64/arm64/')"; \
				TMP_DIR="$$(mktemp -d)"; \
				(cd "$$TMP_DIR" && \
				curl -sSLO "https://github.com/terraform-linters/tflint/releases/latest/download/tflint_linux_$$ARCH.zip" && \
				curl -sSLO https://github.com/terraform-linters/tflint/releases/latest/download/checksums.txt && \
				sha256sum --ignore-missing -c checksums.txt && \
				unzip -q "tflint_linux_$$ARCH.zip" && \
				sudo install -c tflint /usr/local/bin/); \
				rm -rf "$$TMP_DIR"; ;; \
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

check: ## Show which tools are installed and their versions
	@for tool in terraform aws jq; do \
		if command -v $$tool >/dev/null 2>&1; then printf '✅ %-10s %s\n' $$tool "$$($$tool --version 2>&1 | head -n1)"; \
		else printf '❌ %-10s not installed, run make install-tools\n' $$tool; fi; \
	done
	@for tool in tflint checkov assume; do \
		if command -v $$tool >/dev/null 2>&1; then printf '✅ %-10s %s\n' $$tool "$$($$tool --version 2>&1 | head -n1)"; \
		else printf '⚠️  %-10s not installed (optional)\n' $$tool; fi; \
	done

##@ Validation

validate-full: fmt-check validate lint security-scan ## Run every check: formatting, validate, TFLint, and Checkov
	@echo "✅ All validation checks passed"

format: ## Format all Terraform files
	terraform fmt -recursive

fmt-check: ## Check that all Terraform files are formatted
	@terraform fmt -check -recursive || { echo "❌ Some files need formatting. Run: make format" >&2; exit 1; }

validate: ## Validate every environment without touching remote state
	@failed=0; \
	for env in $(ENVIRONMENTS); do \
		echo "🔍 Validating $$env"; \
		(cd environments/$$env && terraform init -backend=false -input=false >/dev/null && terraform validate) || failed=1; \
	done; \
	exit $$failed

validate-env: require-env ## Validate one environment (ENV=<env>)
	cd $(ENV_DIR) && terraform validate $(ARGS)

lint: ## Run TFLint on all Terraform code
	@command -v tflint >/dev/null 2>&1 || { echo "❌ TFLint not installed. Run: make install-tools" >&2; exit 1; }
	tflint --init
	tflint --recursive --format compact

security-scan: ## Run the Checkov security scan
	@command -v checkov >/dev/null 2>&1 || { echo "❌ Checkov not installed. Run: make install-tools" >&2; exit 1; }
	checkov -d . --config-file .checkov.yml --compact --quiet

##@ Deployment (ENV=<environment>)

require-env:
	@test -n "$(ENV)" || { echo "❌ Set ENV, for example: make $(firstword $(MAKECMDGOALS)) ENV=test" >&2; exit 1; }
	@test -d "$(ENV_DIR)" || { echo "❌ Environment '$(ENV)' does not exist. Available: $(or $(ENVIRONMENTS),none (run make setup))" >&2; exit 1; }

init: require-env ## Initialize Terraform (add ARGS="-upgrade" to update providers)
	cd $(ENV_DIR) && terraform init $(ARGS)

plan: require-env ## Show the changes Terraform would make
	cd $(ENV_DIR) && terraform plan $(ARGS)

apply: require-env ## Apply the changes
	cd $(ENV_DIR) && terraform apply $(ARGS)

destroy: require-env ## Destroy all resources in the environment
	cd $(ENV_DIR) && terraform destroy $(ARGS)

##@ Cleanup

cleanup: ## Run the interactive cleanup script
	@./scripts/cleanup.sh
