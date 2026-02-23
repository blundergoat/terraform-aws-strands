# =============================================================================
# SECRETS MODULE VARIABLES
# =============================================================================

variable "project_name" {
  description = "Project name for secret path prefixes"
  type        = string
}

variable "environment" {
  type = string
}

variable "api_key" {
  description = "API key for authenticating agent requests"
  type        = string
  sensitive   = true
}

variable "recovery_window_in_days" {
  description = "Recovery window in days for secret deletion (0 deletes immediately)"
  type        = number
  default     = 0
}

variable "tags" {
  type    = map(string)
  default = {}
}
