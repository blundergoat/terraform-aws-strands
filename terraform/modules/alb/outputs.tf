# =============================================================================
# ALB MODULE OUTPUTS
# =============================================================================

output "alb_dns_name" {
  description = "Public DNS name of the Application Load Balancer"
  value       = aws_lb.this.dns_name
}

output "alb_arn" {
  description = "ARN of the ALB"
  value       = aws_lb.this.arn
}

output "alb_zone_id" {
  description = "ALB hosted zone ID (for Route53 alias records)"
  value       = aws_lb.this.zone_id
}

output "target_group_arn" {
  description = "Target group ARN for the ECS service"
  value       = aws_lb_target_group.agent.arn
}

output "target_group_arn_suffix" {
  description = "Target group ARN suffix (for CloudWatch alarm dimensions)"
  value       = aws_lb_target_group.agent.arn_suffix
}

output "alb_arn_suffix" {
  description = "ALB ARN suffix (for CloudWatch alarm dimensions)"
  value       = aws_lb.this.arn_suffix
}

output "mercure_target_group_arn" {
  description = "Target group ARN for the Mercure SSE hub (empty when disabled)"
  value       = var.enable_mercure ? aws_lb_target_group.mercure[0].arn : ""
}
