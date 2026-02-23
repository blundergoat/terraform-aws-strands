# =============================================================================
# SECURITY MODULE VARIABLES
# =============================================================================

variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  description = "ID of the VPC to create security groups in"
  type        = string
}

variable "alb_ingress_cidrs" {
  description = "Allowed CIDR ranges for inbound ALB traffic"
  type        = list(string)
  default     = []
}

variable "app_port" {
  description = "Port the app listens on (container port)"
  type        = number
  default     = 8000
}

variable "ecs_egress_cidrs" {
  description = "CIDR ranges for ECS task egress (e.g., 0.0.0.0/0 for Bedrock API)"
  type        = list(string)
  default     = []
}

variable "mercure_port" {
  description = "Port for the Mercure SSE hub (0 to disable Mercure SG rules)"
  type        = number
  default     = 0
}

variable "tags" {
  type    = map(string)
  default = {}
}
