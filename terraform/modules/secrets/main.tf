# =============================================================================
# SECRETS MODULE - Secrets Manager Storage
# =============================================================================
#
# Stores application secrets (API keys, JWT secrets, etc.) in AWS Secrets
# Manager. Accepts a list of secret names and a sensitive map of values.
#
# STATE MIGRATION (existing deployments):
#   If upgrading from the single-secret version of this module, run:
#     terraform state mv 'module.secrets.aws_secretsmanager_secret.api_key' \
#       'module.secrets.aws_secretsmanager_secret.this["api-key"]'
#     terraform state mv 'module.secrets.aws_secretsmanager_secret_version.api_key' \
#       'module.secrets.aws_secretsmanager_secret_version.this["api-key"]'
#
# =============================================================================

resource "aws_secretsmanager_secret" "this" {
  for_each = toset(var.secret_names)

  name                    = "/${var.project_name}/${var.environment}/${each.key}"
  description             = "${each.key} for ${var.project_name} ${var.environment}"
  recovery_window_in_days = var.recovery_window_in_days

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-${each.key}"
  })
}

resource "aws_secretsmanager_secret_version" "this" {
  for_each = toset(var.secret_names)

  secret_id     = aws_secretsmanager_secret.this[each.key].id
  secret_string = var.secret_values[each.key]
}
