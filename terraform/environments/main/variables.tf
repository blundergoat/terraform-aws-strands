# =============================================================================
# PROD ENVIRONMENT VARIABLES - All Configurable Settings
# =============================================================================

# =============================================================================
# Core Settings
# =============================================================================

variable "aws_profile" {
  description = "AWS CLI profile name (leave empty to use default credentials)"
  type        = string
  default     = ""
}

# us-east-1 default: broadest Bedrock model availability and lowest latency
# for cross-region inference profiles.
variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "Err: aws_region must be a valid AWS region (e.g., us-east-1)"
  }
}

variable "environment" {
  description = "Environment name (dev or prod). Controls deletion protection, debug mode, and autoscaling."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "Err: environment must be dev or prod"
  }
}

variable "project_name" {
  description = "Project name used in resource naming and tags"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Err: project_name should only contain a-z, 0-9, or hyphens"
  }
}

# =============================================================================
# VPC - Looked up by tag name OR passed as IDs
# =============================================================================

variable "vpc_name" {
  description = "VPC tag:Name to look up via data source (e.g., 'My VPC'). Leave empty to use vpc_id instead."
  type        = string
  default     = ""
}

variable "vpc_id" {
  description = "VPC ID (used only when vpc_name is empty)"
  type        = string
  default     = ""
}

variable "public_subnet_tag_pattern" {
  description = "Tag:Name pattern for public subnets (e.g., '*Public*'). Leave empty to use public_subnet_ids instead."
  type        = string
  default     = ""
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for ALB (used only when public_subnet_tag_pattern is empty)"
  type        = list(string)
  default     = []
}

variable "private_subnet_tag_pattern" {
  description = "Tag:Name pattern for private subnets (e.g., '*Private*'). Leave empty to use private_subnet_ids instead."
  type        = string
  default     = ""
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for ECS tasks (used only when private_subnet_tag_pattern is empty)"
  type        = list(string)
  default     = []
}

# =============================================================================
# DNS / Domain Settings
# =============================================================================

variable "hosted_zone" {
  description = "Root domain name for DNS and certificate"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]+[a-z0-9]$", var.hosted_zone))
    error_message = "Err: hosted_zone must be a valid domain name"
  }
}

variable "subdomain" {
  description = "Subdomain for the application endpoint"
  type        = string
  default     = "app"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.subdomain))
    error_message = "Err: subdomain should only contain a-z, 0-9, or hyphens"
  }
}

variable "create_hosted_zone" {
  description = "Set to true to create a new Route53 hosted zone"
  type        = bool
  default     = false
}

variable "hosted_zone_id" {
  description = "Existing Route53 hosted zone ID (required when create_hosted_zone is false)"
  type        = string
  default     = ""
}

# =============================================================================
# Networking Settings
# =============================================================================

# Open by default because WAF provides the primary protection layer.
# Restrict to specific CIDRs for internal-only deployments.
variable "alb_ingress_cidrs" {
  description = "CIDRs allowed to reach the ALB"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "ecs_egress_cidrs" {
  description = "Egress CIDRs for ECS tasks (needs internet for Bedrock API)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# 120s: Bedrock streaming responses can exceed the 60s default, especially for
# long-running agent tool-use chains. ALB closes idle connections after this.
variable "alb_idle_timeout_seconds" {
  description = "ALB idle timeout (120s for streaming responses)"
  type        = number
  default     = 120
}

# =============================================================================
# Agent Settings
# =============================================================================

# "us." prefix selects a cross-region inference profile, routing requests to the
# nearest available region for lower latency and higher throughput.
variable "model_id" {
  description = "Bedrock model ID for the agent"
  type        = string
  default     = "us.anthropic.claude-sonnet-4-20250514-v1:0"
}

variable "agent_image_tag" {
  description = "Docker image tag for the agent container"
  type        = string
  default     = "latest"
}

variable "ecr_repository_name" {
  description = "ECR repository name for the agent image"
  type        = string
  default     = ""
}

variable "ecr_image_tag_mutability" {
  description = "ECR image tag mutability (MUTABLE or IMMUTABLE). Empty = auto-detect from environment (MUTABLE for dev, IMMUTABLE for prod)."
  type        = string
  default     = ""

  validation {
    condition     = contains(["", "MUTABLE", "IMMUTABLE"], var.ecr_image_tag_mutability)
    error_message = "Err: ecr_image_tag_mutability must be MUTABLE, IMMUTABLE, or empty (auto-detect)"
  }
}

# =============================================================================
# App Settings (web UI sidecar)
# =============================================================================

variable "app_image_tag" {
  description = "Docker image tag for the app container"
  type        = string
  default     = "latest"
}

variable "ecr_app_repository_name" {
  description = "ECR repository name for the app image"
  type        = string
  default     = ""
}

variable "app_log_retention_days" {
  description = "Retention for app task logs (in days)"
  type        = number
  default     = 14
}

# =============================================================================
# Mercure Settings (SSE streaming hub)
# =============================================================================

variable "mercure_image" {
  description = "Docker image for the Mercure SSE hub (e.g., dunglas/mercure)"
  type        = string
  default     = "dunglas/mercure"
}

variable "mercure_log_retention_days" {
  description = "Retention for Mercure container logs (in days)"
  type        = number
  default     = 14
}

# =============================================================================
# DynamoDB Settings
# =============================================================================

variable "dynamodb_table_name" {
  description = "DynamoDB table name for session persistence (auto-generated if empty)"
  type        = string
  default     = ""
}

# =============================================================================
# Security Settings
# =============================================================================

variable "api_key" {
  description = "API key for authenticating agent requests (auto-generated if empty)"
  type        = string
  default     = ""
  sensitive   = true
}

# 0 = immediate deletion for fast dev iteration. Set to 7-30 in production
# to allow secret recovery after accidental deletion.
variable "secrets_recovery_window_days" {
  description = "Secrets Manager deletion window (0 for immediate)"
  type        = number
  default     = 0
}

# =============================================================================
# Observability Settings
# =============================================================================

variable "enable_container_insights" {
  description = "Enable ECS Container Insights for detailed metrics"
  type        = bool
  default     = false
}

variable "agent_log_retention_days" {
  description = "Retention for agent task logs (in days)"
  type        = number
  default     = 14
}

# =============================================================================
# Alerting Settings
# =============================================================================

variable "alarm_email" {
  description = "Email address for CloudWatch alarm notifications"
  type        = string
  default     = ""
}

# =============================================================================
# WAF Settings
# =============================================================================

# 2000 per 5-min window = ~6-7 req/sec sustained per IP. High enough for normal
# browsing + SSE connections, low enough to throttle automated abuse.
variable "waf_rate_limit" {
  description = "WAF rate limit - max requests per 5 minutes per IP"
  type        = number
  default     = 2000
}

# =============================================================================
# CI/CD Settings (GitHub Actions OIDC)
# =============================================================================

variable "github_repository" {
  description = "GitHub repository for OIDC (format: owner/repo)"
  type        = string
  default     = ""
}
