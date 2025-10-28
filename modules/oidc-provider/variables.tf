# Variables for GitHub Actions OIDC Provider Module

variable "use_existing_oidc_provider" {
  description = "Whether to use an existing OIDC provider instead of creating a new one"
  type        = bool
  default     = false
}

variable "github_repo" {
  description = "GitHub repository name in the format 'owner/repo'"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+$", var.github_repo))
    error_message = "GitHub repository must be in the format 'owner/repo'."
  }
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

variable "role_name" {
  description = "Name of the IAM role for GitHub Actions"
  type        = string
  default     = "GitHubActionsServiceRole-Terraform"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]+$", var.role_name))
    error_message = "Role name must contain only alphanumeric characters and +=,.@_-"
  }
}

variable "path" {
  description = "Path for the IAM role"
  type        = string
  default     = "/"

  validation {
    condition     = can(regex("^/.*/$", var.path)) || var.path == "/"
    error_message = "Path must start and end with /"
  }
}

variable "managed_policy_arns" {
  description = "List of IAM managed policy ARNs to attach to the role"
  type        = list(string)
  default     = []
}

variable "inline_policies" {
  description = "Map of inline policy names to policy documents (JSON strings)"
  type        = map(string)
  default     = {}
}

variable "max_session_duration" {
  description = "Maximum session duration in seconds (3600-43200)"
  type        = number
  default     = 3600

  validation {
    condition     = var.max_session_duration >= 3600 && var.max_session_duration <= 43200
    error_message = "Max session duration must be between 3600 and 43200 seconds."
  }
}

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}
