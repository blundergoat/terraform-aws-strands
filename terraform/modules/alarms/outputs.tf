# =============================================================================
# ALARMS MODULE OUTPUTS
# =============================================================================

output "sns_topic_arn" {
  description = "ARN of the SNS topic for alarm notifications"
  value       = aws_sns_topic.alerts.arn
}

output "sns_kms_key_arn" {
  description = "ARN of the customer-managed KMS key used for SNS topic encryption"
  value       = aws_kms_key.sns.arn
}

output "sns_kms_key_id" {
  description = "ID of the customer-managed KMS key used for SNS topic encryption"
  value       = aws_kms_key.sns.id
}
