# =============================================================================
# ECS MODULE VARIABLES
# =============================================================================

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "enable_container_insights" {
  type    = bool
  default = false
}

variable "agent_task_family" {
  description = "Task family name for the agent"
  type        = string
  default     = "agent"
}

variable "agent_image" {
  description = "Full image URI (ECR repo + tag)"
  type        = string
}

variable "agent_container_name" {
  description = "Container name within the task definition"
  type        = string
  default     = "agent"
}

variable "agent_container_port" {
  description = "Container port exposed to the ALB target group"
  type        = number
  default     = 8000
}

variable "cpu" {
  description = "CPU units for Fargate task (increase when running app sidecar)"
  type        = number
  default     = 512
}

variable "memory" {
  description = "Memory (MiB) for Fargate task (increase when running app sidecar)"
  type        = number
  default     = 1024
}

variable "execution_role_arn" {
  description = "Execution role ARN (pull images, write logs)"
  type        = string
}

variable "task_role_arn" {
  description = "Task role ARN (app permissions - Bedrock, DynamoDB)"
  type        = string
}

variable "log_group_name_agent" {
  description = "CloudWatch log group for agent tasks"
  type        = string
}

variable "region" {
  description = "AWS region for log configuration"
  type        = string
}

variable "environment_variables" {
  description = "Plaintext env vars passed to the agent container"
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = "Secrets injected into agent container from Secrets Manager/SSM"
  type = list(object({
    name      = string
    valueFrom = string
  }))
  default = []
}

variable "health_check_command" {
  description = "Agent container health check command"
  type        = list(string)
  default     = ["CMD-SHELL", "curl -f http://localhost:8000/health || exit 1"]
}

# =============================================================================
# APP SIDECAR VARIABLES (optional - set app_image to enable)
# =============================================================================

variable "app_image" {
  description = "Full image URI for the app (empty = no app sidecar)"
  type        = string
  default     = ""
}

variable "app_container_name" {
  description = "Container name for the app within the task definition"
  type        = string
  default     = "app"
}

variable "app_container_port" {
  description = "Container port for the app"
  type        = number
  default     = 8080
}

variable "log_group_name_app" {
  description = "CloudWatch log group for app container logs"
  type        = string
  default     = ""
}

variable "app_environment_variables" {
  description = "Plaintext env vars passed to the app container"
  type        = map(string)
  default     = {}
}

variable "app_secrets" {
  description = "Secrets injected into app container from Secrets Manager/SSM"
  type = list(object({
    name      = string
    valueFrom = string
  }))
  default = []
}

variable "app_health_check_command" {
  description = "App container health check command"
  type        = list(string)
  default     = ["CMD-SHELL", "curl -f http://localhost:8080/ || exit 1"]
}

# =============================================================================
# MERCURE SIDECAR VARIABLES (optional - set mercure_image to enable)
# =============================================================================

variable "mercure_image" {
  description = "Docker image for the Mercure hub (empty = no Mercure sidecar)"
  type        = string
  default     = ""
}

variable "mercure_container_name" {
  description = "Container name for Mercure within the task definition"
  type        = string
  default     = "mercure"
}

variable "mercure_container_port" {
  description = "Container port for the Mercure hub"
  type        = number
  default     = 3701
}

variable "log_group_name_mercure" {
  description = "CloudWatch log group for Mercure container logs"
  type        = string
  default     = ""
}

variable "mercure_environment_variables" {
  description = "Plaintext env vars passed to the Mercure container"
  type        = map(string)
  default     = {}
}

variable "mercure_secrets" {
  description = "Secrets injected into Mercure container from Secrets Manager/SSM"
  type = list(object({
    name      = string
    valueFrom = string
  }))
  default = []
}

variable "mercure_health_check_command" {
  description = "Mercure container health check command"
  type        = list(string)
  default     = ["CMD-SHELL", "curl -f http://localhost:3701/healthz || exit 1"]
}
