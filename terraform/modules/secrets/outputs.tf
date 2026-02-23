# =============================================================================
# SECRETS MODULE OUTPUTS
# =============================================================================

output "api_key_secret_arn" {
  description = "ARN of the API key secret in Secrets Manager"
  value       = aws_secretsmanager_secret.api_key.arn
}

output "api_key_secret_name" {
  description = "Name of the API key secret in Secrets Manager"
  value       = aws_secretsmanager_secret.api_key.name
}
