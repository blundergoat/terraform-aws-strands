# =============================================================================
# OBSERVABILITY MODULE OUTPUTS
# =============================================================================

output "agent_log_group_name" {
  description = "CloudWatch log group name for agent container logs"
  value       = aws_cloudwatch_log_group.agent.name
}

output "agent_log_group_arn" {
  description = "CloudWatch log group ARN for agent container logs"
  value       = aws_cloudwatch_log_group.agent.arn
}

output "app_log_group_name" {
  description = "CloudWatch log group name for app container logs"
  value       = aws_cloudwatch_log_group.app.name
}

output "app_log_group_arn" {
  description = "CloudWatch log group ARN for app container logs"
  value       = aws_cloudwatch_log_group.app.arn
}

output "mercure_log_group_name" {
  description = "CloudWatch log group name for Mercure container logs"
  value       = aws_cloudwatch_log_group.mercure.name
}

output "mercure_log_group_arn" {
  description = "CloudWatch log group ARN for Mercure container logs"
  value       = aws_cloudwatch_log_group.mercure.arn
}
