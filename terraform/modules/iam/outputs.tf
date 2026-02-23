# =============================================================================
# IAM MODULE OUTPUTS
# =============================================================================

output "task_execution_role_arn" {
  description = "ARN of the ECS task execution role (for pulling images, fetching secrets)"
  value       = aws_iam_role.task_execution.arn
}

output "task_role_arn" {
  description = "ARN of the ECS task role (for Bedrock, DynamoDB access)"
  value       = aws_iam_role.task.arn
}

output "github_actions_role_arn" {
  description = "ARN of the GitHub Actions OIDC role (set as AWS_ROLE_ARN secret)"
  value       = var.github_repository != "" ? aws_iam_role.github_actions[0].arn : ""
}
