# =============================================================================
# OBSERVABILITY MODULE VARIABLES
# =============================================================================

variable "project_name" {
  description = "Project name used in log group naming"
  type        = string
}

variable "environment" {
  type = string
}

variable "agent_log_retention_days" {
  description = "Retention for agent task logs (in days)"
  type        = number
  default     = 14
}

variable "app_log_retention_days" {
  description = "Retention for app task logs (in days)"
  type        = number
  default     = 14
}

variable "mercure_log_retention_days" {
  description = "Retention for Mercure container logs (in days)"
  type        = number
  default     = 14
}

variable "tags" {
  type    = map(string)
  default = {}
}
