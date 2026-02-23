# =============================================================================
# SECRETS MODULE - API Key Storage
# =============================================================================
#
# Stores the API key used to authenticate requests to the agent.
#
# =============================================================================

locals {
  secret_path = "/${var.project_name}/${var.environment}/api-key"
}

resource "aws_secretsmanager_secret" "api_key" {
  name                    = local.secret_path
  description             = "API key for ${var.project_name} ${var.environment}"
  recovery_window_in_days = var.recovery_window_in_days

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-api-key"
  })
}

resource "aws_secretsmanager_secret_version" "api_key" {
  secret_id     = aws_secretsmanager_secret.api_key.id
  secret_string = var.api_key
}
