# =============================================================================
# SECRETS MODULE OUTPUTS
# =============================================================================

output "secret_arns" {
  description = "Map of secret name => ARN for all managed secrets"
  value       = { for k, v in aws_secretsmanager_secret.this : k => v.arn }
}

output "secret_names" {
  description = "Map of secret name => Secrets Manager name for all managed secrets"
  value       = { for k, v in aws_secretsmanager_secret.this : k => v.name }
}

# Backward-compatible convenience output for the API key.
output "api_key_secret_arn" {
  description = "ARN of the API key secret in Secrets Manager"
  value       = try(aws_secretsmanager_secret.this["api-key"].arn, null)
}

output "api_key_secret_name" {
  description = "Name of the API key secret in Secrets Manager"
  value       = try(aws_secretsmanager_secret.this["api-key"].name, null)
}
