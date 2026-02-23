# =============================================================================
# ECS MODULE OUTPUTS
# =============================================================================

output "cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = aws_ecs_cluster.this.arn
}

output "cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.this.name
}

output "agent_task_definition_arn" {
  description = "Task definition ARN for the agent service"
  value       = aws_ecs_task_definition.agent.arn
}
