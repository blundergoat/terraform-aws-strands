# =============================================================================
# WAF MODULE OUTPUTS
# =============================================================================

output "web_acl_arn" {
  description = "ARN of the WAF Web ACL"
  value       = aws_wafv2_web_acl.main.arn
}

output "web_acl_id" {
  description = "ID of the WAF Web ACL"
  value       = aws_wafv2_web_acl.main.id
}

output "web_acl_name" {
  description = "Name of the WAF Web ACL"
  value       = aws_wafv2_web_acl.main.name
}

output "log_group_name" {
  description = "CloudWatch Log Group name for WAF logs (if logging enabled)"
  value       = var.enable_logging ? aws_cloudwatch_log_group.waf[0].name : null
}

output "log_group_arn" {
  description = "CloudWatch Log Group ARN for WAF logs (if logging enabled)"
  value       = var.enable_logging ? aws_cloudwatch_log_group.waf[0].arn : null
}
