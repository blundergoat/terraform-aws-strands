---
applyTo: "terraform/modules/**/*.tf"
---

# Terraform Module Conventions

These instructions apply when creating or modifying Terraform modules under
`terraform/modules/`. Every module follows the same structural conventions,
naming patterns, and Terraform idioms.

## Module File Structure

Every module contains exactly these files:

| File           | Purpose                                    |
|----------------|--------------------------------------------|
| `main.tf`      | All resources and data sources              |
| `variables.tf` | All input variables with types and defaults |
| `outputs.tf`   | All outputs exposed to calling modules      |

Do not split resources across multiple files. If a module grows too large,
split it into separate modules instead.

Each file starts with a header block and uses `# ====...` section separators:

```hcl
# =============================================================================
# MODULE NAME - Short Description
# =============================================================================
#
# Multi-line explanation of what this module does.
#
# =============================================================================
```

## Standard Input Variables

Every module that creates named resources accepts these three variables:

```hcl
variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
```

Some focused modules (e.g., `ecr`) accept a direct `repository_name` instead
of `project_name` + `environment` because the caller constructs the name.

## Resource Naming Convention

All named resources follow: `${var.project_name}-${var.environment}-<suffix>`

Computed via a `name_prefix` local:

```hcl
locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

resource "aws_iam_role" "task_execution" {
  name = "${local.name_prefix}-ecs-exec"
}
```

Secrets Manager paths use slashes: `/${var.project_name}/${var.environment}/${each.key}`

Tags use a `Name` key via merge: `tags = merge(var.tags, { Name = "..." })`

## Dynamic Blocks for Optional Features

Use `dynamic "statement"` with conditional `for_each` so policy documents stay
valid even when features are disabled. Three variants from `iam/main.tf`:

**List length check** (include statement only when ARNs are provided):
```hcl
dynamic "statement" {
  for_each = length(var.secrets_arns) > 0 ? [1] : []
  content {
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = var.secrets_arns
  }
}
```

**Boolean feature flag:**
```hcl
dynamic "statement" {
  for_each = var.enable_bedrock_access ? [1] : []
  content {
    sid     = "BedrockInvoke"
    effect  = "Allow"
    actions = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
    resources = length(var.bedrock_model_arns) > 0 ? var.bedrock_model_arns : [
      "arn:aws:bedrock:*::foundation-model/*",
      "arn:aws:bedrock:*:*:inference-profile/*"
    ]
  }
}
```

**Non-empty string check:**
```hcl
dynamic "statement" {
  for_each = var.dynamodb_table_arn != "" ? [1] : []
  content {
    resources = [var.dynamodb_table_arn]
  }
}
```

Rules:
- Always use `for_each = <condition> ? [1] : []` (never `count` on data sources)
- This keeps the policy valid with zero statements when all features are disabled

## The Sensitive for_each Workaround (Secrets Module)

Terraform cannot iterate `for_each` over sensitive values. The secrets module
solves this by splitting into two variables:

```hcl
variable "secret_names" {
  type = list(string)          # NOT sensitive -- safe for plan output
}

variable "secret_values" {
  type      = map(string)
  sensitive = true             # Values never appear in plan output
}
```

Iteration uses the non-sensitive list; values are looked up from the map:

```hcl
resource "aws_secretsmanager_secret" "this" {
  for_each = toset(var.secret_names)
  name     = "/${var.project_name}/${var.environment}/${each.key}"
}

resource "aws_secretsmanager_secret_version" "this" {
  for_each      = toset(var.secret_names)
  secret_id     = aws_secretsmanager_secret.this[each.key].id
  secret_string = var.secret_values[each.key]
}
```

Outputs expose maps keyed by secret name:

```hcl
output "secret_arns" {
  value = { for k, v in aws_secretsmanager_secret.this : k => v.arn }
}
```

## Optional Sidecar Pattern (ECS Module)

The ECS module supports optional containers via ternary-to-null + concat:

```hcl
# Empty image string = disabled. Ternary produces null, not empty map.
local.mercure_container = var.mercure_image != "" ? { ... full definition ... } : null
local.app_container     = var.app_image != "" ? { ... full definition ... } : null

# concat() assembles only active containers
local.container_definitions = concat(
  [local.agent_container],                                          # always present
  local.mercure_container != null ? [local.mercure_container] : [], # optional
  local.app_container != null ? [local.app_container] : []          # optional
)
```

Container dependency ordering uses the same pattern:

```hcl
local.app_depends_on = concat(
  [{ containerName = var.agent_container_name, condition = "HEALTHY" }],
  local.mercure_container != null ? [
    { containerName = var.mercure_container_name, condition = "HEALTHY" }
  ] : []
)
```

Rules:
- Empty string image = feature disabled (variable default is `""`)
- Ternary produces `null` for disabled features, not an empty map
- `concat()` with `!= null ? [x] : []` is the standard list-assembly pattern
- Variables for optional sidecars go in a separate section with a comment header

## Output Conventions

Three patterns used across modules:

1. **Map outputs** for multi-resource modules: `{ for k, v in resource.this : k => v.arn }`
2. **Convenience outputs** for common lookups: `try(resource.this["key"].arn, null)`
3. **Simple pass-through**: `aws_ecr_repository.this.repository_url`

Use `try(..., null)` when an output depends on a key that may not exist.

## Variable Declaration Conventions

- Always specify `type` -- never rely on inference
- Always include `description` for non-obvious variables
- Defaults: `[]` for lists, `""` for strings, `{}` for maps, `false` for bools
- Required variables have no `default` attribute
- Group related variables under `# === SECTION NAME ===` headers
- Mark `sensitive = true` only for actual secret data
- Optional features default to their "disabled" state

## IAM Policy Best Practices

- Use `aws_iam_policy_document` data sources, not inline JSON (except OIDC
  trust policies where `jsonencode` is clearer)
- `resources` is always a list: `resources = [var.dynamodb_table_arn]`
- Use `Resource = "*"` only when the API does not support resource-level
  permissions, and document why with a comment
- Pass multiple ARNs as `list(string)` variables

## Common Gotchas

**Sensitive values cannot be for_each keys.** If you mark a `map(string)` as
`sensitive` and use it in `for_each`, Terraform errors. Use the split-variable
pattern (see secrets module above).

**IAM Resource field requires a list.** `resources = var.dynamodb_table_arn`
(string) fails. Use `resources = [var.dynamodb_table_arn]` (list).

**count vs for_each.** Use `count = condition ? 1 : 0` only for singleton
optional resources (e.g., GitHub OIDC provider). Never use `count` to iterate
a list -- index-based tracking causes destroy/recreate drift on reorder.

**tostring() for Fargate CPU/memory.** Fargate requires strings but numbers
are more natural in variables. Use `cpu = tostring(var.cpu)`.

**Health check startPeriod varies by container.** Agent (Python/ML): 60s.
App (web UI): 30s. Mercure (Go binary): 15s.

## Never Do This

- **Do not hardcode ARNs.** They break across accounts, regions, and partitions.
  Use variables or data sources.
- **Do not use count to iterate lists.** Adding/removing items renumbers everything.
  Use `for_each = toset(var.list)` instead.
- **Do not mark map variables as sensitive if they will be used in for_each.**
  Split into non-sensitive key list + sensitive value map.
- **Do not put resource logic in environment root modules.** Environments are
  orchestration layers. All infrastructure logic belongs in modules.
- **Do not inline JSON policies when aws_iam_policy_document works.** Reserve
  `jsonencode()` for simple static structures like OIDC trust policies.

## See Also

- `CLAUDE.md` -- repository-wide conventions and workflow rules
- `docs/architecture.md` -- full architecture overview and deployment guide
