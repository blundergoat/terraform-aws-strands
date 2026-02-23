# =============================================================================
# DYNAMODB MODULE VARIABLES
# =============================================================================

variable "table_name" {
  description = "Name of the DynamoDB table for session persistence"
  type        = string
  default     = "sessions"
}

variable "tags" {
  type    = map(string)
  default = {}
}
