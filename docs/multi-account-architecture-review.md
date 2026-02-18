# AWS Terraform Starter Kit: Multi-Account Architecture Review

Date: 2026-02-18  
Repository: `towardsthecloud/aws-terraform-starter-kit`  
Reviewer lens: AWS/Terraform production readiness for multi-account (test + production minimum)

## Scope and method

This review focused on:

- Terraform module design (`modules/oidc-provider`)
- Environment/bootstrap generation logic (`scripts/setup.sh`)
- CI/CD workflow architecture (`.github/workflows/*` + generated workflow template in `setup.sh`)
- Operational controls (`Makefile`, `scripts/cleanup.sh`, lint/security config)

Current repo state is a starter scaffold; `environments/` currently contains only `.gitkeep`.

## Executive summary

The project is a useful starter for quickly bootstrapping Terraform + GitHub OIDC in AWS, but it is **not yet production-ready for secure multi-account operations** without hardening.

The largest blockers are:

1. Overly broad OIDC trust and permissions model.
2. Unsafe CI trigger pattern using `pull_request_target` with AWS credentials.
3. Missing explicit environment-to-account guardrails.

If those are fixed first, the kit can become a solid base for test/staging/prod in separate AWS accounts.

## What is already solid

- Remote state backend uses S3 with versioning, encryption, and public access blocking (`scripts/setup.sh`).
- State key pattern is environment-scoped (`environments/<env>/terraform.tfstate`).
- OIDC-based auth avoids static AWS keys (`modules/oidc-provider`).
- Built-in lint/security hooks exist (TFLint + Checkov reusable workflows).

## Findings (prioritized)

## Critical

### 1) OIDC trust policy is too broad for production

Evidence:

- `modules/oidc-provider/main.tf`: `github_subject_claim = "repo:${var.github_repo}:*"`

Impact:

- Any branch/ref/workflow in the repo can potentially assume the same high-privilege role.
- Weak boundary between low-trust PR context and production deployment path.

Recommendation:

- Restrict trust policy conditions to explicit refs/environments.
- Use separate IAM roles per environment (at minimum `test` and `production`), and separate trust conditions.
- Add conditions for repository owner, branch/tag constraints, and optional GitHub environment claim where applicable.

### 2) Generated workflow pattern is vulnerable (`pull_request_target` + checkout head + AWS creds)

Evidence:

- `scripts/setup.sh` generated workflow:
  - Trigger: `pull_request_target`
  - Checks out `github.event.pull_request.head.sha`
  - Has `id-token: write`
  - Assumes AWS role in plan job

Impact:

- Untrusted PR content can be executed in a privileged workflow context.
- This is a known dangerous pattern for cloud credentials exposure and account abuse.

Recommendation:

- Do not run Terraform plan with cloud credentials on untrusted PR head under `pull_request_target`.
- Split workflow model:
  - `pull_request` job for fmt/validate/static checks (no AWS credentials).
  - Protected plan/apply flow using trusted refs only (e.g., merge queue/main, or manually approved workflow_dispatch).
- If PR comments are required, use safer, least-privilege plan role and trusted execution model.

### 3) Default IAM policy is `AdministratorAccess`

Evidence:

- `scripts/setup.sh` generated `terraform.tfvars` and `variables.tf` default include:
  - `arn:aws:iam::aws:policy/AdministratorAccess`

Impact:

- Violates least privilege by default.
- Increases blast radius across each target account.

Recommendation:

- Replace default policy set with scoped Terraform execution permissions.
- Create separate plan vs apply roles:
  - Plan: read/list + specific describe actions.
  - Apply: targeted write actions per module stack.

## High

### 4) Environment/account mapping is implicit, not enforced

Evidence:

- `scripts/setup.sh` embeds `AWS_ACCOUNT_ID`, `AWS_REGION`, and `TF_STATE_BUCKET` defaults into generated workflows.
- Same variable names are used for all environments.

Impact:

- Easy to misconfigure and accidentally deploy an environment to the wrong AWS account.
- Operational drift risk increases as environments scale.

Recommendation:

- Introduce explicit mapping file (e.g., `config/environments.yaml`) with required keys:
  - `environment`, `account_id`, `region`, `state_bucket`, `role_name`
- Generate workflow/env files from that single source of truth.
- Add validation step that fails if STS account does not match intended environment.

### 5) Security scanning is soft-fail in generated deployment workflows

Evidence:

- `scripts/setup.sh` generated workflow calls Checkov reusable workflow with `soft_fail: true`.

Impact:

- Known high/critical issues may not block deployment.

Recommendation:

- Make security checks fail-closed for protected branches/environments.
- Optionally keep soft-fail only for developer branches.

### 6) OIDC provider ownership model can cause lifecycle coupling

Evidence:

- First environment may create/manage OIDC provider; others use existing provider (`use_existing_oidc_provider` flow in `setup.sh`).
- `cleanup.sh` warns that destroying one environment may remove shared OIDC provider.

Impact:

- Environment lifecycle is not independent.
- Destructive operations can break other environments in same account unexpectedly.

Recommendation:

- Manage shared identity primitives in a separate “account bootstrap” stack.
- Environments should consume bootstrap outputs, not own shared provider lifecycle.

## Medium

### 7) Backend bootstrap is imperative shell, not Terraform-managed

Evidence:

- S3 backend bucket creation and policy configuration happen via `aws s3api` in `scripts/setup.sh`.

Impact:

- Harder to audit, review, and drift-correct.
- Less reproducible for enterprise onboarding.

Recommendation:

- Move backend/bootstrap resources to dedicated Terraform bootstrap stack per account.
- Keep setup script as orchestrator, not source of infrastructure truth.

### 8) Inconsistent Terraform version constraints

Evidence:

- Module requires `>= 1.5.0` (`modules/oidc-provider/versions.tf`).
- Generated environment config requires `>= 1.10` (`scripts/setup.sh` template).

Impact:

- Potential confusion in tooling and CI/runtime expectations.

Recommendation:

- Standardize on one explicit minimum version across module + generated environments.

### 9) Workflow status-summary steps use brittle `$?` logic

Evidence:

- Reusable workflow summaries and generated deployment summary steps check `$?` in separate commands.

Impact:

- Can produce misleading success/failure messaging in step summaries.

Recommendation:

- Capture step outcome using `${{ job.status }}` or explicit `if: success()/failure()` blocks.

### 10) Static OIDC thumbprint default may age poorly

Evidence:

- `modules/oidc-provider/variables.tf` sets fixed default thumbprint.

Impact:

- Certificate chain changes could require urgent manual updates.

Recommendation:

- Validate/refresh thumbprint management strategy and document update procedure.

## Multi-account target architecture (recommended)

## 1) Account model

- One AWS account per environment (`test`, `staging`, `production`).
- One state bucket per account (or centralized with strict partitioning if governance allows, but per-account is simpler and safer).
- One OIDC provider per account.

## 2) IAM role model

- Per-environment roles:
  - `GitHubActionsTerraformPlan-<env>`
  - `GitHubActionsTerraformApply-<env>`
- Strict trust conditions per environment and allowed refs.
- Least-privilege policies per role.

## 3) CI/CD model

- `pull_request`: fmt/validate/tflint/checkov only, no AWS credentials.
- Trusted plan/apply workflows:
  - Main branch, merge queue, or approved manual dispatch.
  - GitHub Environments for approval gates (especially production).

## 4) Configuration model

- Single declarative environment/account config file.
- Generated workflow and Terraform environment files must be derived from that config.
- Add pre-flight account assertion: STS account must equal configured account for target environment.

## Issue-ready improvement backlog

## P0 (blockers before production rollout)

1. Replace `pull_request_target` design with secure PR workflow model.
2. Remove `AdministratorAccess` defaults; implement least-privilege IAM policies.
3. Split plan/apply IAM roles and tighten OIDC trust conditions.
4. Add explicit environment-to-account mapping and validation gates.
5. Set security checks to fail-closed for protected deployments.

## P1 (strongly recommended next)

1. Move backend bootstrap to Terraform-managed account bootstrap stack.
2. Separate shared identity primitives from environment stacks.
3. Standardize Terraform version constraints across module/templates.
4. Improve workflow status handling and failure reporting.

## P2 (maturity)

1. Add drift detection workflow and periodic plan checks.
2. Add policy-as-code enforcement (e.g., OPA/Conftest or custom Checkov policy baseline).
3. Add module/unit/integration validation for generated environment templates.

## Suggested acceptance criteria for issues

- “Cannot assume production apply role from non-main refs.”
- “PR workflows from forks never receive cloud credentials.”
- “Each environment has immutable configured account ID, validated before init/plan/apply.”
- “No default admin policies anywhere in generated templates.”
- “Destroying one environment cannot delete shared identity primitives unexpectedly.”

## Final verdict

Foundation quality: **Good starter, not yet safe multi-account production baseline**.  
With P0 and P1 implemented, this can become a robust template for test/staging/production across separate AWS accounts.
