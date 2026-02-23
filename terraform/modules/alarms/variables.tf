# =============================================================================
# ALARMS MODULE VARIABLES
# =============================================================================

variable "project_name" {
  description = "Project name for alarm naming"
  type        = string
}

variable "environment" {
  type = string
}

variable "alb_arn_suffix" {
  description = "ALB ARN suffix (from aws_lb.arn_suffix)"
  type        = string
}

variable "target_group_arn_suffix" {
  description = "Target group ARN suffix (from aws_lb_target_group.arn_suffix)"
  type        = string
}

variable "ecs_cluster_name" {
  description = "ECS cluster name for Container Insights alarms"
  type        = string
}

variable "ecs_service_name" {
  description = "ECS service name for Container Insights alarms"
  type        = string
}

variable "alarm_email" {
  description = "Optional email address for alarm notifications"
  type        = string
  default     = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}
