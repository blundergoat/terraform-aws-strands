# AGENTS.md

This file provides guidance to AI coding agents when working with code in this repository.

## Project Identity

Terraform (>= 1.5.0) + AWS Provider 5.x infrastructure for deploying a Strands Agents app on ECS Fargate. Three containers (agent :8000, app :8080, Mercure SSE :3701) in one task behind ALB + WAF + Route53.

## Essential Commands

```bash
./scripts/preflight-checks.sh                                # fmt + validate (no AWS creds needed)
./scripts/terraform.sh plan -var-file=staging.tfvars          # preview changes
./scripts/terraform.sh apply -var-file=staging.tfvars         # apply changes
APP_DIR=/path/to/app ./scripts/deploy.sh                     # build + push + redeploy
```

## Hard Rules

- **Validate before committing.** Run `./scripts/preflight-checks.sh` after any `.tf` change.
- **Never pass secrets as plaintext env vars.** Use Secrets Manager + ECS container `secrets` blocks. See the secrets flow in `terraform/environments/main/main.tf`.
- **Sensitive values cannot be for_each keys.** Split into non-sensitive key list + sensitive value map. See `terraform/modules/secrets/`.
- **Check for circular deps when wiring IAM.** The IAM module spans dependency phases — trace the chain before adding references. See `docs/footguns.md`.
- **IAM Resource fields must be lists** when granting access to multiple resources (e.g., ECR repos).
- **Never commit** `backend.hcl`, `.tfvars`, secrets, or state files.
- **Log footguns.** When you cause a bug that spans multiple domains (e.g., IAM + ECS, secrets + modules), append it to `docs/footguns.md` using the existing format before closing the task.

## Common Workflows

**Add a new module:**
1. Create `terraform/modules/<name>/` with main.tf, variables.tf, outputs.tf
2. Accept `project_name`, `environment`, `tags` — name resources `${project_name}-${environment}-<suffix>`
3. Wire into correct phase in `terraform/environments/main/main.tf`
4. Run `./scripts/preflight-checks.sh`

**Add a new secret:**
1. Add name to `secret_names` list and value to `secret_values` map in the `module "secrets"` block
2. Wire `module.secrets.secret_arns["<name>"]` into the target container's `secrets` or `app_secrets` or `mercure_secrets`
3. Ensure `secrets_arns` passed to IAM includes the new ARN (already uses `values(module.secrets.secret_arns)`)

## Commit Style

`type: short summary` — e.g., `fix: scope Bedrock IAM to anthropic model family`. Prefer small, scoped commits by module or concern.

## Router Table

| File | Read when... |
|---|---|
| **Domain Guides** | |
| `.github/instructions/terraform-modules.instructions.md` | Writing or modifying a Terraform module |
| `.github/instructions/terraform-environment.instructions.md` | Wiring modules in the root environment or changing dependency phases |
| **Architecture & Reference** | |
| `docs/architecture.md` | Understanding how components connect, request flow, or deployment pipeline |
| `docs/code-map.md` | Navigating the repository structure or finding a file |
| `docs/footguns.md` | Before making cross-domain changes (IAM+ECS, secrets+modules, ECR+CI) |
| **Operations** | |
| `scripts/terraform.sh` | Debugging Terraform wrapper behavior or adding new commands |
| `scripts/deploy.sh` | Debugging Docker build/push/redeploy or adding deployment targets |
| `README.md` | Answering user-facing questions about setup, prerequisites, or outputs |
