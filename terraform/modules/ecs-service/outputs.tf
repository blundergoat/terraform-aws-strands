# =============================================================================
# ECS SERVICE MODULE OUTPUTS
# =============================================================================

output "service_arn" {
  description = "ARN of the ECS service"
  value       = aws_ecs_service.this.id
}

output "service_name" {
  description = "Name of the ECS service"
  value       = aws_ecs_service.this.name
}
