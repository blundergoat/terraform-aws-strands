# =============================================================================
# ECS SERVICE MODULE VARIABLES
# =============================================================================

variable "cluster_arn" {
  description = "ARN of the ECS cluster to deploy the service to"
  type        = string
}

variable "service_name" {
  type = string
}

variable "task_definition_arn" {
  type = string
}

variable "desired_count" {
  type    = number
  default = 1
}

variable "subnet_ids" {
  type = list(string)
}

variable "security_group_ids" {
  type = list(string)
}

variable "target_group_arn" {
  type = string
}

variable "container_name" {
  type    = string
  default = "agent"
}

variable "container_port" {
  type    = number
  default = 8000
}

# =============================================================================
# Mercure Target Group (optional)
# =============================================================================

variable "mercure_target_group_arn" {
  description = "Target group ARN for the Mercure SSE hub (empty to skip)"
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

# =============================================================================
# Autoscaling (optional)
# =============================================================================

variable "enable_autoscaling" {
  description = "Enable CPU/memory target tracking autoscaling"
  type        = bool
  default     = false
}

variable "autoscaling_min" {
  description = "Minimum number of tasks"
  type        = number
  default     = 1
}

variable "autoscaling_max" {
  description = "Maximum number of tasks"
  type        = number
  default     = 4
}

variable "cpu_target_value" {
  description = "Target CPU utilization percentage for scaling"
  type        = number
  default     = 50
}

variable "memory_target_value" {
  description = "Target memory utilization percentage for scaling"
  type        = number
  default     = 60
}

variable "tags" {
  type    = map(string)
  default = {}
}
