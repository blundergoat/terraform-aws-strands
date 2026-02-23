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

variable "secret_names" {
  description = "List of secret names to create in Secrets Manager"
  type        = list(string)
}

variable "secret_values" {
  description = "Map of secret name => secret value (must contain all keys from secret_names)"
  type        = map(string)
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
