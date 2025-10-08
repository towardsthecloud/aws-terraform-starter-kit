# AWS Terraform Starter Kit

An AWS Terraform Starter Kit that includes predefined Terraform configurations, secure state management, and development tools, along with CI/CD pipelines optimized for GitHub Actions, enabling you to quickly and securely deploy scalable AWS infrastructure on your account.

## 🚀 Features

- **Complete Terraform Setup**: Pre-configured Terraform files with AWS provider
- **Secure State Management**: S3 backend with DynamoDB locking for state files
- **Dummy Resource Deployment**: S3 bucket with security best practices as demo
- **Development Tools**: Makefile and shell scripts for common operations
- **CI/CD Pipeline**: GitHub Actions workflow for automated deployments
- **Security Best Practices**: Encrypted storage, public access blocks, and proper IAM
- **Comprehensive Documentation**: Step-by-step guides and examples

## 📋 Prerequisites

Before you begin, ensure you have the following installed:

- [Terraform](https://www.terraform.io/downloads.html) (>= 1.0)
- [AWS CLI](https://aws.amazon.com/cli/) (>= 2.0)
- [Make](https://www.gnu.org/software/make/) (optional, for using Makefile)

## 🔧 Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/towardsthecloud/aws-terraform-starter-kit.git
cd aws-terraform-starter-kit
```

### 2. Configure AWS Credentials

Configure your AWS credentials using one of these methods:

**Option A: AWS CLI**
```bash
aws configure
```

**Option B: Environment Variables**
```bash
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="us-east-1"
```

**Option C: IAM Role (for EC2/ECS/Lambda)**
Attach an appropriate IAM role to your compute resource.

### 3. Setup and Deploy

**Quick Setup (using scripts):**
```bash
./scripts/setup.sh
./scripts/deploy.sh
```

**Manual Setup (using Makefile):**
```bash
make setup      # Copy example files
make deploy     # Full deployment workflow
```

**Step-by-step Setup:**
```bash
# Copy and edit configuration
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# Initialize and deploy
terraform init
terraform plan
terraform apply
```

## 📁 Project Structure

```
├── main.tf                 # Main Terraform configuration
├── variables.tf            # Input variables
├── outputs.tf              # Output values
├── terraform.tf            # Terraform and provider configuration
├── backend.tf              # Remote state backend configuration
├── terraform.tfvars.example # Example variables file
├── Makefile               # Common operations
├── scripts/
│   ├── setup.sh           # Setup script
│   ├── deploy.sh          # Deployment script
│   └── cleanup.sh         # Cleanup script
├── .github/workflows/
│   └── terraform.yml      # GitHub Actions CI/CD
└── README.md              # This file
```

## 🛠️ Usage

### Makefile Commands

```bash
make help       # Show available commands
make setup      # Initial setup (copy example files)
make init       # Initialize Terraform
make validate   # Validate configuration
make format     # Format Terraform files
make plan       # Create execution plan
make apply      # Apply changes
make destroy    # Destroy resources
make clean      # Clean local files
make deploy     # Full deployment workflow
make check      # Check tool versions
```

### Scripts

```bash
./scripts/setup.sh      # Interactive setup
./scripts/deploy.sh     # Interactive deployment
./scripts/cleanup.sh    # Interactive cleanup
```

## ⚙️ Configuration

### Variables

Edit `terraform.tfvars` to customize your deployment:

```hcl
# AWS region for resources
aws_region = "us-east-1"

# Environment name
environment = "dev"

# Project name
project_name = "my-awesome-project"

# S3 bucket name (optional, auto-generated if empty)
bucket_name = ""

# Common tags
tags = {
  Terraform   = "true"
  Environment = "dev"
  Project     = "my-awesome-project"
  Owner       = "your-name"
  Department  = "engineering"
}
```

### Remote State Backend

After the initial deployment, you can migrate to remote state:

1. Note the state bucket and DynamoDB table names from outputs
2. Uncomment the backend configuration in `terraform.tf`
3. Update the bucket and table names
4. Run `terraform init` to migrate state

```hcl
backend "s3" {
  bucket         = "your-project-terraform-state-xxxxx"
  key            = "terraform/state.tfstate"
  region         = "us-east-1"
  dynamodb_table = "your-project-terraform-state-lock"
  encrypt        = true
}
```

## 🔒 Security Features

- **S3 Bucket Encryption**: Server-side encryption enabled
- **S3 Public Access Block**: Prevents accidental public access
- **S3 Versioning**: Enabled for data protection
- **DynamoDB State Locking**: Prevents concurrent modifications
- **IAM Best Practices**: Minimal required permissions
- **Encrypted State Storage**: State files encrypted at rest

## 🚀 CI/CD Pipeline

The included GitHub Actions workflow provides:

- **Terraform Validation**: Format and syntax checking
- **Security Scanning**: Basic security checks
- **Plan Generation**: For pull requests
- **Automated Deployment**: For main branch pushes

### Setup GitHub Actions

1. Add AWS credentials to GitHub Secrets:
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`

2. Update workflow file if needed:
   - Modify AWS region
   - Adjust branch names
   - Add environment protection rules

## 📝 What Gets Deployed

This starter kit deploys:

1. **Demo S3 Bucket**: A secure S3 bucket with best practices
2. **Demo S3 Object**: A sample text file in the bucket
3. **State Management**: S3 bucket and DynamoDB table for Terraform state
4. **Security Settings**: Encryption, versioning, and access controls

## 🧹 Cleanup

To remove all resources:

```bash
# Using script (interactive)
./scripts/cleanup.sh

# Using Makefile
make destroy

# Using Terraform directly
terraform destroy
```

## 🔧 Customization

### Adding Resources

1. Add new resources to `main.tf` or create new `.tf` files
2. Add required variables to `variables.tf`
3. Add outputs to `outputs.tf`
4. Update `terraform.tfvars.example` with new variables

### Modifying the Demo

Replace the S3 bucket with your preferred demo resource:
- EC2 instances
- RDS databases
- Lambda functions
- VPC networking

## 📚 Learn More

- [Terraform Documentation](https://www.terraform.io/docs/)
- [AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Terraform Best Practices](https://www.terraform.io/docs/cloud/guides/recommended-practices/index.html)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## 📄 License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

If you encounter any issues:

1. Check the [GitHub Issues](https://github.com/towardsthecloud/aws-terraform-starter-kit/issues)
2. Review the Terraform and AWS documentation
3. Ensure your AWS credentials and permissions are correct
4. Verify all prerequisites are installed

## 🎯 Next Steps

After successful deployment:

1. **Explore Outputs**: Review the deployed resources
2. **Customize Configuration**: Modify variables and add resources
3. **Setup Remote State**: Migrate to S3 backend for team collaboration
4. **Implement CI/CD**: Configure GitHub Actions for your workflow
5. **Add Monitoring**: Implement CloudWatch, alerting, and logging
6. **Scale Up**: Add more complex AWS resources and modules

---

Happy Terraforming! 🎉
