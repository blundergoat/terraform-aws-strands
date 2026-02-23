# =============================================================================
# OBSERVABILITY MODULE - Logging Infrastructure
# =============================================================================
#
# Creates CloudWatch Log Groups for ECS containers:
#   - Agent (Python FastAPI)
#   - App (web UI, optional)
#   - Mercure (SSE hub, optional)
#
# =============================================================================

locals {
  agent_log_group   = "/ecs/${var.project_name}-${var.environment}-agent"
  app_log_group     = "/ecs/${var.project_name}-${var.environment}-app"
  mercure_log_group = "/ecs/${var.project_name}-${var.environment}-mercure"
}

resource "aws_cloudwatch_log_group" "agent" {
  name              = local.agent_log_group
  retention_in_days = var.agent_log_retention_days

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "app" {
  name              = local.app_log_group
  retention_in_days = var.app_log_retention_days

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "mercure" {
  name              = local.mercure_log_group
  retention_in_days = var.mercure_log_retention_days

  tags = var.tags
}
