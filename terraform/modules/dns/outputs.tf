# =============================================================================
# DNS MODULE OUTPUTS
# =============================================================================

output "certificate_arn" {
  description = "ARN of the validated ACM certificate"
  value       = aws_acm_certificate_validation.this.certificate_arn
}

output "hosted_zone_id" {
  description = "Route53 hosted zone ID"
  value       = local.zone_id
}
