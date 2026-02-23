# =============================================================================
# ENVIRONMENT OUTPUTS - Important Values After Deployment
# =============================================================================

output "alb_dns_name" {
  description = "Public DNS name of the ALB (test before DNS propagates)"
  value       = module.alb.alb_dns_name
}

output "ecr_agent_repository_url" {
  description = "ECR repository URL for agent images"
  value       = module.ecr.repository_url
}

output "ecr_app_repository_url" {
  description = "ECR repository URL for app images"
  value       = module.ecr_app.repository_url
}

output "api_key_secret_name" {
  description = "Secrets Manager secret name for the API key"
  value       = module.secrets.api_key_secret_name
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = module.ecs.cluster_name
}

output "ecs_service_name" {
  description = "Name of the ECS service"
  value       = module.ecs_service.service_name
}

output "agent_task_definition_arn" {
  description = "ARN of the agent task definition"
  value       = module.ecs.agent_task_definition_arn
}

output "hosted_zone_id" {
  description = "Route53 hosted zone ID"
  value       = module.dns.hosted_zone_id
}

output "ecs_security_group_id" {
  description = "Security group ID for ECS tasks"
  value       = module.security.ecs_security_group_id
}

output "github_actions_role_arn" {
  description = "IAM role ARN for GitHub Actions OIDC (set as AWS_ROLE_ARN secret)"
  value       = module.iam.github_actions_role_arn
}

output "dynamodb_table_name" {
  description = "DynamoDB sessions table name"
  value       = module.dynamodb.table_name
}

output "app_url" {
  description = "Application endpoint URL"
  value       = "https://${var.subdomain}.${var.hosted_zone}"
}
