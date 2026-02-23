---
applyTo: "terraform/environments/**/*.tf"
---

# Terraform Environment Configuration Conventions

These instructions apply when creating or modifying environment configurations
under `terraform/environments/`. Environment root modules orchestrate all
infrastructure modules and wire them together. They contain no resource logic
of their own beyond simple glue (DNS records, random passwords).

## Environment File Structure

Each environment directory contains exactly three files:

| File           | Purpose                                                  |
|----------------|----------------------------------------------------------|
| `main.tf`      | Provider config, locals, module calls, data sources, DNS |
| `variables.tf` | All user-facing configuration variables with validation   |
| `outputs.tf`   | Important values surfaced after `terraform apply`         |

If the environment is growing too complex, extract a new module rather than
adding files.

## The 6-Phase Dependency Order

Module calls in `main.tf` are organized into six phases based on dependency
relationships. This ordering must be respected when adding new modules:

```
Phase 1: Independent resources (no cross-module dependencies)
  - dynamodb, ecr, ecr_app, observability, secrets

Phase 2: Security and IAM (needs VPC ID, secret ARNs)
  - security, iam

Phase 3: ECS and DNS (needs IAM roles, observability log groups, ECR URLs)
  - ecs, dns

Phase 4: ALB (needs security groups, DNS certificate, VPC/subnets)
  - alb

Phase 5: ECS Service, WAF, DNS Records (needs ECS cluster, ALB, security)
  - ecs_service, waf, Route53 A/AAAA records

Phase 6: Alarms (needs ALB and ECS identifiers)
  - alarms
```

Terraform resolves dependencies implicitly via reference chains, but the code
is organized so humans can understand the build order. Placing a module in the
wrong phase can create circular dependencies Terraform cannot resolve.

### The IAM Module Spans Multiple Phases

The IAM module lives in Phase 2 for core role definitions (task execution role,
task role), but its GitHub OIDC deploy policy references Phase 3-5 outputs:

```hcl
module "iam" {
  source = "../../modules/iam"
  # Phase 1 inputs (available immediately)
  secrets_arns       = values(module.secrets.secret_arns)
  dynamodb_table_arn = module.dynamodb.table_arn

  # Phase 3-5 inputs (Terraform resolves via implicit dependencies)
  ecs_cluster_arn      = module.ecs.cluster_arn
  ecs_service_arn      = module.ecs_service.service_arn
  ecr_repository_arns  = [module.ecr.repository_arn, module.ecr_app.repository_arn]
  log_group_arns       = ["${module.observability.agent_log_group_arn}:*", ...]
  alb_target_group_arn = module.alb.target_group_arn
}
```

This works because IAM role resources only depend on Phase 1 outputs, while
OIDC resources (using `count`) depend on Phase 3-5 outputs. Terraform's
dependency graph resolves this. But if you add an IAM variable that is both
consumed by ECS *and* produced by ECS, you create a cycle.

## VPC Resolution Pattern

Two strategies for locating VPC and subnets:

**Strategy 1: Tag-based lookup (recommended)**
```hcl
data "aws_vpc" "by_name" {
  count = var.vpc_name != "" ? 1 : 0
  filter {
    name   = "tag:Name"
    values = [var.vpc_name]
  }
}

data "aws_subnets" "public" {
  count = var.public_subnet_tag_pattern != "" ? 1 : 0
  filter { name = "vpc-id"; values = [local.resolved_vpc_id] }
  filter { name = "tag:Name"; values = [var.public_subnet_tag_pattern] }
}
```

**Strategy 2: Explicit IDs (fallback)** -- pass `vpc_id`, `public_subnet_ids`,
`private_subnet_ids` directly.

Resolution locals pick whichever strategy has a value:

```hcl
locals {
  resolved_vpc_id             = var.vpc_name != "" ? data.aws_vpc.by_name[0].id : var.vpc_id
  resolved_public_subnet_ids  = var.public_subnet_tag_pattern != "" ? data.aws_subnets.public[0].ids : var.public_subnet_ids
  resolved_private_subnet_ids = var.private_subnet_tag_pattern != "" ? data.aws_subnets.private[0].ids : var.private_subnet_ids
}
```

Always use `local.resolved_*` in module calls -- never reference the raw
variables or data sources directly.

## Environment Detection Pattern

A single `isDev` local drives all environment-specific behavior:

```hcl
locals {
  isDev = var.environment == "dev"
  env   = var.environment
}
```

Used throughout as ternary expressions:

```hcl
ecr_image_tag_mutability   = local.isDev ? "MUTABLE" : "IMMUTABLE"
enable_deletion_protection = !local.isDev
APP_DEBUG                  = local.isDev ? "1" : "0"
enable_autoscaling         = !local.isDev
```

Always use `local.isDev` for new environment-sensitive defaults. Never add a
separate detection mechanism. The `environment` variable validates to only
accept `"dev"` or `"prod"`.

## How Secrets Flow Through the Stack

Four-step pipeline from generation to container injection:

**Step 1 -- Generate values:**
```hcl
resource "random_password" "api_key" { length = 32; special = false }
resource "random_password" "app_secret" { length = 32; special = false }
resource "random_password" "mercure_jwt_secret" { length = 32; special = false }

locals {
  api_key_value = var.api_key != "" ? var.api_key : random_password.api_key.result
}
```

**Step 2 -- Store in Secrets Manager:**
```hcl
module "secrets" {
  source       = "../../modules/secrets"
  secret_names = ["api-key", "app-secret", "mercure-jwt-secret"]
  secret_values = {
    "api-key"            = local.api_key_value
    "app-secret"         = random_password.app_secret.result
    "mercure-jwt-secret" = random_password.mercure_jwt_secret.result
  }
}
```

**Step 3 -- Grant IAM access:**
```hcl
module "iam" {
  secrets_arns = values(module.secrets.secret_arns)
}
```

**Step 4 -- Inject into ECS containers:**
```hcl
module "ecs" {
  secrets = [
    { name = "API_KEY", valueFrom = module.secrets.api_key_secret_arn }
  ]
  app_secrets = [
    { name = "APP_SECRET", valueFrom = module.secrets.secret_arns["app-secret"] },
    { name = "MERCURE_JWT_SECRET", valueFrom = module.secrets.secret_arns["mercure-jwt-secret"] }
  ]
  mercure_secrets = [
    { name = "MERCURE_PUBLISHER_JWT_KEY", valueFrom = module.secrets.secret_arns["mercure-jwt-secret"] },
    { name = "MERCURE_SUBSCRIBER_JWT_KEY", valueFrom = module.secrets.secret_arns["mercure-jwt-secret"] }
  ]
}
```

ECS resolves `valueFrom` ARNs at container start time using the task execution
role's `secretsmanager:GetSecretValue` permission.

## How to Add a New Module

1. **Create the module** under `terraform/modules/<name>/` with `main.tf`,
   `variables.tf`, and `outputs.tf`.
2. **Determine the correct phase** -- the earliest phase where all inputs are
   available. Needs nothing? Phase 1. Needs VPC/IAM? Phase 2. And so on.
3. **Add the module block** under the correct phase section header:
   ```hcl
   module "my_new_module" {
     source       = "../../modules/my-new-module"
     project_name = var.project_name
     environment  = local.env
     tags         = local.tags
   }
   ```
4. **Pass standard variables**: `project_name`, `environment` (as `local.env`),
   `tags` (as `local.tags`).
5. **Wire outputs** to downstream modules if needed.
6. **Add environment outputs** in `outputs.tf` for values users need after apply.
7. **Add input variables** in `variables.tf` with type, description, default,
   and validation.

## How to Add a New Secret

Changes required in three places within `main.tf`:

**Step 1 -- Generate the value:**
```hcl
resource "random_password" "my_new_secret" { length = 32; special = false }
```

**Step 2 -- Add to secrets module** (both `secret_names` and `secret_values`):
```hcl
module "secrets" {
  secret_names = ["api-key", "app-secret", "mercure-jwt-secret", "my-new-secret"]
  secret_values = {
    # ... existing entries ...
    "my-new-secret" = random_password.my_new_secret.result
  }
}
```

**Step 3 -- Wire to container:**
```hcl
module "ecs" {
  secrets = [
    { name = "API_KEY", valueFrom = module.secrets.api_key_secret_arn },
    { name = "MY_NEW_SECRET", valueFrom = module.secrets.secret_arns["my-new-secret"] }
  ]
}
```

The `name` field becomes the env var inside the container. Both `secret_names`
and `secret_values` must stay in sync -- every name needs a matching value key.

## Container Environment Variables vs Secrets

**Plaintext env vars** (non-sensitive config) are defined in `locals` and passed
as maps:
```hcl
locals {
  agent_env = {
    PORT = "8000"; MODEL_ID = var.model_id; DYNAMODB_TABLE = module.dynamodb.table_name
  }
}
module "ecs" { environment_variables = local.agent_env }
```

**Secrets** (credentials, tokens, keys) go through Secrets Manager as
`{name, valueFrom}` objects. Never pass sensitive values as plaintext env vars.

## Provider Configuration

```hcl
provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile != "" ? var.aws_profile : null
  default_tags { tags = local.tags }
}
```

The `default_tags` block applies `Project`, `Env`, and `ManagedBy` tags to all
resources. Module-level `tags` receive `local.tags` for consistent tagging via
`merge(var.tags, {...})`.

## Variable Conventions

- Use `validation` blocks for constrained values (catches errors at plan time)
- Group variables by section: Core, VPC, DNS, Networking, Agent, App, Mercure,
  DynamoDB, Security, Observability, Alerting, WAF, CI/CD
- Auto-detect defaults use the pattern: explicit value > auto-generated name
  ```hcl
  ecr_agent_name = var.ecr_repository_name != "" ? var.ecr_repository_name : "${var.project_name}-agent"
  ```
- Output descriptions should explain *what to do* with the value, not just what
  it is (e.g., "set as AWS_ROLE_ARN secret" not just "GitHub Actions role ARN")

## Common Gotchas

**IAM module spans phases -- watch for cycles.** It accepts Phase 1 and Phase
3-5 inputs. Adding an IAM output consumed by a module that also feeds IAM
creates a circular dependency.

**Wrong phase = circular deps.** If module A (Phase 3) needs module B's output,
B must be Phase 1 or 2. Placing B in Phase 4 while B also needs A creates a
cycle.

**secret_names and secret_values must stay in sync.** A mismatch causes a
runtime error: `var.secret_values[each.key]` fails for missing keys.

**Log group ARN suffix.** Append `:*` when passing log group ARNs to IAM:
```hcl
log_group_arns = ["${module.observability.agent_log_group_arn}:*", ...]
```
Without `:*`, the policy won't match log stream ARNs and reads fail with
access denied.

**Use local.env, not var.environment.** Always pass `local.env` to modules for
consistency and future-proofing.

## Never Do This

- **Do not put resource logic in environment files.** Only `random_password`,
  `aws_route53_record` (DNS glue), and VPC/subnet data sources belong here.
  Everything else goes in a module.
- **Do not pass secrets as plaintext env vars.** They appear in the ECS task
  definition, AWS Console, API responses, and Terraform state. Use Secrets
  Manager.
- **Do not hardcode AWS account IDs or regions.** Use variables, data sources,
  and wildcard ARNs where appropriate.
- **Do not create multiple provider blocks for the same region.** Use aliased
  providers only for cross-region resources.
- **Do not use Terraform workspaces.** This repo uses separate directories per
  environment with `.tfvars` files, each with its own state.
- **Do not skip variable validation.** Every constrained variable needs a
  `validation` block.

## See Also

- `CLAUDE.md` -- repository-wide conventions and workflow rules
- `docs/architecture.md` -- full architecture overview and deployment guide
