# =============================================================================
# ALB MODULE VARIABLES
# =============================================================================

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "alb_security_group_id" {
  type = string
}

variable "certificate_arn" {
  type = string
}

variable "target_port" {
  description = "Target port for the primary service (8080 for app, 8000 for agent-only)"
  type        = number
  default     = 8000
}

variable "health_check_path" {
  description = "Health check path for the target group"
  type        = string
  default     = "/health"
}

variable "enable_deletion_protection" {
  type    = bool
  default = false
}

variable "internal" {
  type    = bool
  default = false
}

variable "idle_timeout" {
  description = "Idle timeout in seconds (120s default for streaming)"
  type        = number
  default     = 120
}

variable "tags" {
  type    = map(string)
  default = {}
}

# =============================================================================
# Mercure SSE Hub (optional path-based routing)
# =============================================================================

variable "enable_mercure" {
  description = "Enable a second target group and listener rule for Mercure SSE hub"
  type        = bool
  default     = false
}

variable "mercure_target_port" {
  description = "Target port for the Mercure container"
  type        = number
  default     = 3701
}

variable "mercure_health_check_path" {
  description = "Health check path for the Mercure target group"
  type        = string
  default     = "/healthz"
}
