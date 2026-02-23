# =============================================================================
# IAM MODULE VARIABLES
# =============================================================================

variable "project_name" {
  description = "Project name for IAM role naming"
  type        = string
}

variable "environment" {
  type = string
}

variable "secrets_arns" {
  description = "Secrets Manager ARNs the tasks should read"
  type        = list(string)
  default     = []
}

variable "kms_key_arns" {
  description = "KMS keys to decrypt SecureString parameters"
  type        = list(string)
  default     = []
}

variable "enable_bedrock_access" {
  description = "Enable Bedrock model invocation permissions for the task role"
  type        = bool
  default     = true
}

variable "dynamodb_table_arn" {
  description = "DynamoDB table ARN for session persistence (empty to skip)"
  type        = string
  default     = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}

# =============================================================================
# GITHUB OIDC VARIABLES
# =============================================================================

variable "github_repository" {
  description = "GitHub repository in format 'owner/repo' for OIDC trust"
  type        = string
  default     = ""
}

variable "ecr_repository_arn" {
  description = "ECR repository ARN for push permissions"
  type        = string
  default     = ""
}

variable "ecs_cluster_arn" {
  description = "ECS cluster ARN for deploy permissions"
  type        = string
  default     = ""
}

variable "ecs_service_arn" {
  description = "ECS service ARN for deploy permissions"
  type        = string
  default     = ""
}

variable "log_group_arns" {
  description = "CloudWatch log group ARNs for reading logs"
  type        = list(string)
  default     = []
}

variable "alb_target_group_arn" {
  description = "ALB target group ARN for health check permissions"
  type        = string
  default     = ""
}
