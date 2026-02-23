# Footguns

Cross-domain issues that have bitten us or will bite you. AI agents: read this before making changes, and append new entries when you cause a bug that spans multiple domains.

## Footgun: Sensitive values in for_each

**Symptoms:** `terraform validate` fails with "Sensitive values, or values derived from sensitive values, cannot be used as for_each arguments." Plan never runs.

**Why it happens:** Terraform prohibits sensitive values as `for_each` keys because keys appear in state file resource addresses (e.g., `aws_secretsmanager_secret.this["api-key"]`). A `map(string)` variable marked `sensitive = true` makes the entire map — including keys — sensitive, even though only the values contain secrets.

**Prevention:** Split into two variables: a non-sensitive `list(string)` for the keys (used in `for_each = toset(...)`) and a separate `sensitive` `map(string)` for the values (used only in resource attributes). See `terraform/modules/secrets/` for the canonical pattern. Never mark a map variable as `sensitive` if its keys will be used in `for_each` or `count`.

## Footgun: ECR push policy scoped to single repo

**Symptoms:** GitHub Actions CI/CD can push agent images but fails on app images with "AccessDeniedException" on ECR push. The IAM policy looks correct at first glance.

**Why it happens:** The IAM OIDC deploy policy's `ECRPush` statement accepts an ECR ARN for the `Resource` field. If this is a single string instead of a list, only one repository gets push permissions. When you have multiple ECR repos (agent + app), the second repo silently gets no access.

**Prevention:** Always use `list(string)` for IAM `Resource` fields that reference multiple resources. Check that all ECR repos are included when adding a new container/image to the stack. See `ecr_repository_arns` in `terraform/modules/iam/`.

## Footgun: Secrets module state migration on upgrade

**Symptoms:** `terraform plan` shows destroy + recreate for existing Secrets Manager secrets after upgrading the secrets module from single-secret to map-based. This deletes the live secret, causing container startup failures.

**Why it happens:** The resource address changes from `aws_secretsmanager_secret.api_key` to `aws_secretsmanager_secret.this["api-key"]`. Terraform sees these as different resources and plans a destroy/create cycle.

**Prevention:** Run `terraform state mv` before applying. The exact commands are documented in `terraform/modules/secrets/main.tf` header comment. Always check `terraform plan` for unexpected destroys on secrets, IAM roles, or any resource that other services depend on at runtime.

## Footgun: IAM module circular dependencies

**Symptoms:** `terraform plan` fails with a dependency cycle error after adding a new module reference to the IAM module.

**Why it happens:** The IAM module spans multiple dependency phases. Task roles (phase 2) are consumed by ECS (phase 3), but the GitHub OIDC policy references ECS cluster/service ARNs (phase 3-5) and ALB target group (phase 4). Adding a reference to a module that itself depends on IAM creates a cycle.

**Prevention:** Before wiring a new output into the IAM module, trace the dependency chain. If the new module depends on `module.iam.task_role_arn` or `task_execution_role_arn`, you cannot also pass its outputs back to IAM without creating a cycle. The OIDC policy can reference downstream modules because it doesn't feed back into ECS task creation. See the phase diagram in `docs/architecture.md`.
