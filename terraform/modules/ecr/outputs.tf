# =============================================================================
# ECR MODULE OUTPUTS
# =============================================================================

output "repository_url" {
  description = "Full ECR repository URL for docker push/pull"
  value       = aws_ecr_repository.this.repository_url
}

output "repository_arn" {
  description = "ARN of the ECR repository"
  value       = aws_ecr_repository.this.arn
}
