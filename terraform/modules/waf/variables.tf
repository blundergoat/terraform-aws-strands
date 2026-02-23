# =============================================================================
# WAF MODULE VARIABLES
# =============================================================================

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  type = string
}

variable "alb_arn" {
  description = "ARN of the ALB to associate with the WAF"
  type        = string
  default     = ""
}

variable "associate_alb" {
  description = "Whether to create the WAF-ALB association (avoids count on computed values)"
  type        = bool
  default     = true
}

variable "rate_limit" {
  description = "Maximum requests per 5-minute period per IP before blocking"
  type        = number
  default     = 2000
}

variable "block_anonymous_ips" {
  description = "Whether to block requests from anonymous IPs (Tor, proxies)"
  type        = bool
  default     = false
}

variable "common_rules_excluded" {
  description = "List of rule names to exclude from the Common Rule Set"
  type        = list(string)
  default     = []
}

variable "enable_logging" {
  description = "Enable CloudWatch logging for blocked requests"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

variable "tags" {
  type    = map(string)
  default = {}
}
