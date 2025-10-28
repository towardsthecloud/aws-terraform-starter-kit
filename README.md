# AWS Terraform Starter Kit

[![AWS](https://img.shields.io/badge/AWS-%23FF9900.svg?style=flat&logo=amazon-aws&logoColor=white)](https://aws.amazon.com/)
[![Terraform](https://img.shields.io/badge/terraform-%235835CC.svg?style=flat&logo=terraform&logoColor=white)](https://www.terraform.io/)
[![TFLint](https://img.shields.io/badge/linting-tflint-blue.svg?style=flat)](https://github.com/terraform-linters/tflint)
[![Checkov](https://img.shields.io/badge/security-checkov-brightgreen.svg?style=flat)](https://www.checkov.io/)

A production-ready AWS Terraform starter kit featuring secure OIDC authentication, automated CI/CD pipelines, multi-environment support, and comprehensive security scanning. Get your infrastructure up and running in minutes with best practices baked in.

## 🚀 Features

- **⚡ One-Command Bootstrap**: Single command automatically sets up your entire infrastructure pipeline
  - Creates S3 + DynamoDB for Terraform state management
  - Generates environment-specific Terraform configurations
  - Provisions OIDC provider for secure keyless authentication
  - Auto-generates GitHub Actions workflows for CI/CD
- **💬 PR Plan Comments**: [Terraform plan outputs](https://github.com/marketplace/actions/terraform-plan-pr-commenter) are automatically posted to your pull requests for easy infrastructure change reviews
- **🛡️ Built-in Security**: TFLint and Checkov are integrated in the pipeline to catch issues before you deploy to AWS

## 📋 Prerequisites

- AWS account with admin access
- GitHub account with repository admin access

**That's it!** All other tools (Terraform, AWS CLI, TFLint, Checkov) can be installed automatically with `make install-tools`.

## 🔧 Quick Start

### ⚠️ Multi-Account Best Practice

**Important**: For production use, deploy each environment to a **separate AWS account**:
- **Test** → AWS Account A (e.g., 111111111111)
- **Staging** → AWS Account B (e.g., 222222222222)
- **Production** → AWS Account C (e.g., 333333333333)

**Why?**
- Security isolation between environments
- Blast radius containment
- Compliance requirements (SOC2, ISO 27001, etc.)
- Cost separation and tracking

### Setup (3 Steps - 5 minutes)

#### 1. Copy the starter kit

1. Click the green ["Use this template"](https://github.com/new?template_name=aws-terraform-starter-kit&template_owner=towardsthecloud) button to create a new repository based on this starter kit.

#### 2. Install required tools

```bash
make install-tools  # Installs Terraform, AWS CLI, TFLint, Checkov, Granted
```

#### 3. Configure AWS Credentials

```bash
# Option A: AWS CLI
aws configure

# Option B: Granted (for multiple accounts)
assume <profile-name>

# Verify you are connected to AWS in the CLI
aws sts get-caller-identity
```

#### 4. Run Setup to provision your Terraform project

```bash
make setup
# Or: ./scripts/setup.sh
```

**What happens:**
1. ✅ Verifies prerequisites e.g. dev tools
2. ✅ Creates S3 backend + DynamoDB table to manage Terraform state
3. ✅ Provisions environment (test/staging/production)
4. ✅ Deploys OIDC provider + IAM role so you can deploy securely via GitHub
5. ✅ Generates GitHub workflow files

**Multi-Account Setup:**
```bash
# Test account
assume test-account
make setup  # Select: test

# Staging account
assume staging-account
make setup  # Select: staging

# Production account
assume prod-account
make setup  # Select: production
```

### Configure GitHub (2 minutes)

#### A. Repository Variables (Optional)

All values are embedded as defaults - only set if you want to override:
- `AWS_ACCOUNT_ID` (already hardcoded)
- `AWS_REGION`
- `TF_STATE_BUCKET`
- `TF_STATE_LOCK_TABLE`

#### B. Environment Protection (Production)

1. Go to **Settings** → **Environments** → **production**
2. Add required reviewers
3. Set deployment branches to `main` only

### Test It (1 minute)

```bash
git checkout -b test-deployment
# Make a small change to environments/test/main.tf
git add . && git commit -m "test: verify pipeline"
git push origin test-deployment
```

✅ GitHub Actions runs automatically
✅ TFLint + Checkov scan
✅ Terraform plan posted to PR
✅ Merge to deploy

## 📁 Project Structure

```
.
├── .github/workflows/          # CI/CD pipelines
│   ├── terraform-deploy-*.yml  # Environment deployments
│   ├── tflint-scan.yml
│   └── checkov-scan.yml
├── environments/               # Environment configs
│   ├── test/
│   ├── staging/
│   └── production/
├── modules/                    # Reusable modules
│   └── oidc-provider/
├── scripts/
│   ├── setup.sh               # Unified setup wizard
│   ├── validate-terraform.sh
│   └── cleanup.sh
└── Makefile                   # All commands
```

## 🛠️ Common Commands

```bash
# Run: make help
make install-tools              # Install dev tools
make setup                      # Complete setup wizard

# Validation
make validate-full              # Run all checks
make lint                       # TFLint only
make security-scan              # Checkov only
make format                     # Format code

# Deployment (specify ENV)
make init ENV=production
make plan ENV=production
make apply ENV=production
make destroy ENV=production

# Utilities
make cleanup                    # Interactive cleanup
make check                      # Check tool versions
make help                       # Show all commands
```

## 🔒 OIDC Provider Management

The setup script automatically handles OIDC providers:

- **Existing OIDC** (manually created): Uses it, doesn't manage it
- **No OIDC**: Creates and manages it with Terraform
- Each environment gets its own IAM role
- Shared OIDC provider across environments in same account (if any)

**Example with existing OIDC:**
```
✅ Found existing OIDC provider: arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com
ℹ️  Environment 'test' will use existing OIDC provider (not managed by Terraform)
```

Result: Terraform only manages IAM role, won't touch OIDC provider

## 🧹 Cleanup

```bash
make cleanup
# or: ./scripts/cleanup.sh
```

**Options:**
1. Destroy environment resources (OIDC, IAM roles)
2. Destroy bootstrap resources (S3, DynamoDB)
3. Clean local cache files
4. Remove source files (environments/, workflows/)
5. Full cleanup (everything)

**OIDC Safety**: The script warns if you're deleting an environment that manages the OIDC provider.

## ✅ Best Practices Implemented

### 🏢 Multi-Account Architecture
- One environment per AWS account
- Security isolation & blast radius containment
- Compliance ready (SOC2, ISO 27001)
- Separate state backends per account

### 🔒 Security
- OIDC authentication (no long-lived credentials)
- Encrypted state files (AES-256)
- S3 versioning & public access blocked
- TLS enforcement on state bucket
- Automated security scanning (Checkov)

### 🚀 CI/CD
- Automated validation on PRs
- Terraform plan posted to PRs
- Environment protection with approvals
- Path-based workflow triggers
- Manual approval for production

### 📝 Code Quality
- Documented & typed variables
- TFLint enforcement
- Consistent naming conventions
- Modular architecture

## 📝 Usage Examples

### Add New Environment

```bash
# Multi-account (recommended)
assume new-account
make setup

# Single account (if needed)
./scripts/setup.sh -e staging -s
```

### Using Existing OIDC Provider

```bash
make setup
# Automatically detects and uses existing OIDC
# Won't manage or destroy it
```

### Validate Before Commit

```bash
make validate-full
# Or individual checks:
make lint
make security-scan
make format
```

### Deploy with Granted

```bash
assume production-admin
make plan ENV=production
make apply ENV=production
```

## 🆘 Troubleshooting

<details>
<summary><b>Multiple environments - best practice?</b></summary>

Deploy each environment to a separate AWS account:

```bash
assume test-account && make setup      # test
assume staging-account && make setup   # staging
assume prod-account && make setup      # production
```

For learning/demo only (single account):
```bash
./scripts/setup.sh -e test,staging,production
# Warning: requires "yes" confirmation
```
</details>

<details>
<summary><b>Existing OIDC provider - will setup break it?</b></summary>

No! Setup automatically detects existing OIDC providers and uses them (won't manage or destroy).
</details>

<details>
<summary><b>Tools not installed?</b></summary>

```bash
make install-tools
# Installs: Terraform, AWS CLI, TFLint, Checkov
```
</details>

<details>
<summary><b>Access denied errors?</b></summary>

```bash
# Verify credentials
aws sts get-caller-identity

# Ensure admin access for setup
# IAM permissions needed: S3, DynamoDB, IAM, OIDC
```
</details>

<details>
<summary><b>GitHub Actions fails "could not assume role"?</b></summary>

1. Ensure setup completed successfully
2. Check workflow file has correct AWS account ID
3. Verify IAM role trust policy includes your repo
4. GitHub variables are optional (defaults embedded in workflows)
</details>

<details>
<summary><b>State locking errors?</b></summary>

```bash
cd environments/<env>
terraform force-unlock <LOCK_ID>
```
</details>

## 🎯 Next Steps

After setup:

1. ✅ Test CI/CD with a pull request
2. ✅ Configure production environment protection
3. ✅ Add your infrastructure modules
4. ✅ Set up additional environments (in separate accounts)
5. ✅ Implement monitoring and alerting
6. ✅ Document your infrastructure

## 📚 Learn More

- [Terraform Documentation](https://www.terraform.io/docs/)
- [AWS Provider Docs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [GitHub OIDC Guide](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [Granted](https://docs.commonfate.io/granted/introduction)
- [TFLint Rules](https://github.com/terraform-linters/tflint-ruleset-aws/blob/master/docs/rules/README.md)
- [Checkov Policies](https://www.checkov.io/5.Policy%20Index/terraform.html)

---

**Built with ❤️ using Terraform and AWS**

For questions or feedback, please [open an issue](https://github.com/towardsthecloud/aws-terraform-starter-kit/issues/new).
