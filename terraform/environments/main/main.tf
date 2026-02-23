# =============================================================================
# PRODUCTION ENVIRONMENT - Main Infrastructure Configuration
# =============================================================================
#
# Root module orchestrating all modules for deploying a Strands Agent stack
# with an optional app sidecar and Mercure SSE hub on AWS ECS Fargate.
#
# Expects a pre-existing VPC with public and private subnets.
# VPC/subnets can be looked up by tag name or passed as explicit IDs.
#
# USAGE:
#   terraform plan -var-file=staging.tfvars
#   terraform plan -var-file=production.tfvars
#
# ARCHITECTURE:
#
#   Route 53 (<subdomain>.<hosted_zone>)
#        |
#        v
#   Application Load Balancer (public subnets)
#        |--- /.well-known/mercure*  ---> Mercure target group (port 3701)
#        |--- default                ---> App target group (port 8080)
#        |
#        v
#   ECS Fargate Task (private subnets)
#     - App container (port 8080)                          <-- ALB default target
#     - Agent container (Python FastAPI, port 8000)        <-- internal sidecar
#     - Mercure container (SSE hub, port 3701)             <-- ALB path-routed
#          |
#          +-- AWS Bedrock (model invocation)
#          +-- DynamoDB (session persistence)
#
# MODULE DEPENDENCY ORDER:
#   1. dynamodb, ecr, ecr_app, observability, secrets (independent)
#   2. security (needs vpc_id), iam (needs phase 1 ARNs)
#   3. ecs (needs iam, observability, ecr), dns (needs hosted_zone_id)
#   4. alb (needs security, dns cert, vpc/subnets)
#   5. ecs_service (needs ecs, alb, security), waf (needs alb)
#   6. alarms (needs alb, ecs)
#
# =============================================================================

provider "aws" {
  region = var.aws_region
  # null falls through to the default credential chain (env vars, instance profile, etc.).
  profile = var.aws_profile != "" ? var.aws_profile : null

  default_tags {
    tags = local.tags
  }
}

# =============================================================================
# Environment Detection & Derived Defaults
# =============================================================================

locals {
  isDev = var.environment == "dev"
  env   = var.environment

  tags = {
    Project   = var.project_name
    Env       = local.env
    ManagedBy = "terraform"
  }

  # Derived resource names -- allows bring-your-own ECR repos (e.g., shared across
  # environments) or auto-generates names from project_name.
  ecr_agent_name = var.ecr_repository_name != "" ? var.ecr_repository_name : "${var.project_name}-agent"
  ecr_app_name   = var.ecr_app_repository_name != "" ? var.ecr_app_repository_name : "${var.project_name}-app"
  dynamodb_name  = var.dynamodb_table_name != "" ? var.dynamodb_table_name : "${var.project_name}-${local.env}-sessions"
  api_key_value  = var.api_key != "" ? var.api_key : random_password.api_key.result
}

# =============================================================================
# VPC and Subnet Lookup (by tag name or explicit IDs)
# =============================================================================

data "aws_vpc" "by_name" {
  count = var.vpc_name != "" ? 1 : 0

  filter {
    name   = "tag:Name"
    values = [var.vpc_name]
  }
}

data "aws_subnets" "public" {
  count = var.public_subnet_tag_pattern != "" ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [local.resolved_vpc_id]
  }

  filter {
    name   = "tag:Name"
    values = [var.public_subnet_tag_pattern]
  }
}

data "aws_subnets" "private" {
  count = var.private_subnet_tag_pattern != "" ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [local.resolved_vpc_id]
  }

  filter {
    name   = "tag:Name"
    values = [var.private_subnet_tag_pattern]
  }
}

# Two resolution strategies: look up subnets by tag pattern (convenient when
# subnets follow a naming convention) or pass explicit IDs (for unusual VPCs).
locals {
  resolved_vpc_id             = var.vpc_name != "" ? data.aws_vpc.by_name[0].id : var.vpc_id
  resolved_public_subnet_ids  = var.public_subnet_tag_pattern != "" ? data.aws_subnets.public[0].ids : var.public_subnet_ids
  resolved_private_subnet_ids = var.private_subnet_tag_pattern != "" ? data.aws_subnets.private[0].ids : var.private_subnet_ids
}

# =============================================================================
# Generated Secrets
# =============================================================================

# Generate an API key unless one is provided via variables.
resource "random_password" "api_key" {
  length  = 32
  special = false
}

# Generate an APP_SECRET for CSRF tokens and session signing.
resource "random_password" "app_secret" {
  length  = 32
  special = false
}

# Generate a JWT secret for Mercure publisher/subscriber authentication.
resource "random_password" "mercure_jwt_secret" {
  length  = 32
  special = false
}

# =============================================================================
# Container Environment Variables
# =============================================================================

locals {
  # Environment variables passed to the agent container.
  agent_env = {
    PORT                         = "8000"
    MODEL_ID                     = var.model_id
    MODEL_PROVIDER               = "bedrock"
    AWS_DEFAULT_REGION           = var.aws_region
    ALLOW_SYSTEM_PROMPT_OVERRIDE = "false"
    DYNAMODB_TABLE               = module.dynamodb.table_name
  }

  # Environment variables passed to the app container.
  app_env = {
    APP_ENV            = local.env
    APP_DEBUG          = local.isDev ? "1" : "0"
    APP_SECRET         = random_password.app_secret.result
    AGENT_ENDPOINT     = "http://localhost:8000"
    MERCURE_URL        = "http://localhost:3701/.well-known/mercure"
    MERCURE_PUBLIC_URL = "https://${var.subdomain}.${var.hosted_zone}/.well-known/mercure"
    MERCURE_JWT_SECRET = random_password.mercure_jwt_secret.result
  }

  # Environment variables for the Mercure sidecar container.
  mercure_env = {
    MERCURE_PUBLISHER_JWT_KEY  = random_password.mercure_jwt_secret.result
    MERCURE_SUBSCRIBER_JWT_KEY = random_password.mercure_jwt_secret.result
    SERVER_NAME                = ":3701"
    MERCURE_EXTRA_DIRECTIVES   = "anonymous\ncors_origins https://${var.subdomain}.${var.hosted_zone}"
  }
}

# =============================================================================
# Phase 1: Independent resources
# =============================================================================

module "dynamodb" {
  source     = "../../modules/dynamodb"
  table_name = local.dynamodb_name
  tags       = local.tags
}

module "ecr" {
  source          = "../../modules/ecr"
  repository_name = local.ecr_agent_name
  # MUTABLE allows overwriting :latest during development. Production pipelines
  # should push unique tags (git SHA) for traceability.
  image_tag_mutability = "MUTABLE"
  tags                 = local.tags
}

module "ecr_app" {
  source               = "../../modules/ecr"
  repository_name      = local.ecr_app_name
  image_tag_mutability = "MUTABLE"
  tags                 = local.tags
}

module "observability" {
  source                     = "../../modules/observability"
  project_name               = var.project_name
  environment                = local.env
  agent_log_retention_days   = var.agent_log_retention_days
  app_log_retention_days     = var.app_log_retention_days
  mercure_log_retention_days = var.mercure_log_retention_days
  tags                       = local.tags
}

module "secrets" {
  source                  = "../../modules/secrets"
  project_name            = var.project_name
  environment             = local.env
  api_key                 = local.api_key_value
  recovery_window_in_days = var.secrets_recovery_window_days
  tags                    = local.tags
}

# =============================================================================
# Phase 2: Security and IAM
# =============================================================================

module "security" {
  source            = "../../modules/security"
  project_name      = var.project_name
  environment       = local.env
  vpc_id            = local.resolved_vpc_id
  alb_ingress_cidrs = var.alb_ingress_cidrs
  app_port          = 8080
  mercure_port      = 3701
  ecs_egress_cidrs  = var.ecs_egress_cidrs
  tags              = local.tags
}

module "iam" {
  source                = "../../modules/iam"
  project_name          = var.project_name
  environment           = local.env
  secrets_arns          = [module.secrets.api_key_secret_arn]
  dynamodb_table_arn    = module.dynamodb.table_arn
  enable_bedrock_access = true
  tags                  = local.tags

  # GitHub OIDC for CI/CD (optional)
  github_repository    = var.github_repository
  ecr_repository_arn   = module.ecr.repository_arn
  ecs_cluster_arn      = module.ecs.cluster_arn
  ecs_service_arn      = module.ecs_service.service_arn
  log_group_arns       = ["${module.observability.agent_log_group_arn}:*", "${module.observability.app_log_group_arn}:*", "${module.observability.mercure_log_group_arn}:*"]
  alb_target_group_arn = module.alb.target_group_arn
}

# =============================================================================
# Phase 3: ECS and DNS
# =============================================================================

module "ecs" {
  source                    = "../../modules/ecs"
  project_name              = var.project_name
  environment               = local.env
  cluster_name              = "${var.project_name}-cluster"
  enable_container_insights = var.enable_container_insights

  # 1 vCPU / 2 GB split across three containers (agent + app + Mercure).
  # This is the smallest Fargate size that avoids OOM with concurrent requests.
  cpu    = 1024
  memory = 2048

  # Agent container (Python FastAPI, internal sidecar)
  agent_image           = "${module.ecr.repository_url}:${var.agent_image_tag}"
  execution_role_arn    = module.iam.task_execution_role_arn
  task_role_arn         = module.iam.task_role_arn
  log_group_name_agent  = module.observability.agent_log_group_name
  region                = var.aws_region
  environment_variables = local.agent_env
  secrets = [
    {
      name      = "API_KEY"
      valueFrom = module.secrets.api_key_secret_arn
    }
  ]

  # App container (ALB target)
  app_image                 = "${module.ecr_app.repository_url}:${var.app_image_tag}"
  log_group_name_app        = module.observability.app_log_group_name
  app_environment_variables = local.app_env

  # Mercure container (SSE hub, ALB path-routed)
  mercure_image                 = var.mercure_image
  log_group_name_mercure        = module.observability.mercure_log_group_name
  mercure_environment_variables = local.mercure_env
}

module "dns" {
  source             = "../../modules/dns"
  domain_name        = var.hosted_zone
  create_hosted_zone = var.create_hosted_zone
  hosted_zone_id     = var.hosted_zone_id
  subdomain          = var.subdomain
  tags               = local.tags
}

# =============================================================================
# Phase 4: ALB
# =============================================================================

module "alb" {
  source                = "../../modules/alb"
  project_name          = var.project_name
  environment           = local.env
  vpc_id                = local.resolved_vpc_id
  public_subnet_ids     = local.resolved_public_subnet_ids
  alb_security_group_id = module.security.alb_security_group_id
  certificate_arn       = module.dns.certificate_arn
  internal              = false
  idle_timeout          = var.alb_idle_timeout_seconds
  # Dev environments skip deletion protection for easy teardown.
  enable_deletion_protection = !local.isDev
  target_port                = 8080
  # "/" returns the app's index page; a dedicated /health endpoint is unnecessary
  # because the app framework returns 500 if unhealthy.
  health_check_path = "/"
  enable_mercure    = true
  tags              = local.tags
}

# =============================================================================
# Phase 5: ECS Service, WAF, DNS Records
# =============================================================================

module "ecs_service" {
  source              = "../../modules/ecs-service"
  cluster_arn         = module.ecs.cluster_arn
  service_name        = "${var.project_name}-app"
  task_definition_arn = module.ecs.agent_task_definition_arn
  desired_count       = 1
  subnet_ids          = local.resolved_private_subnet_ids
  security_group_ids  = [module.security.ecs_security_group_id]
  target_group_arn    = module.alb.target_group_arn
  container_name      = "app"
  container_port      = 8080

  # Mercure SSE hub target group registration
  mercure_target_group_arn = module.alb.mercure_target_group_arn

  # Autoscaling disabled in dev to save cost on a single-developer environment.
  enable_autoscaling  = !local.isDev
  autoscaling_min     = 1
  autoscaling_max     = 4
  cpu_target_value    = 50
  memory_target_value = 60

  tags = local.tags
}

module "waf" {
  source       = "../../modules/waf"
  project_name = var.project_name
  environment  = local.env
  alb_arn      = module.alb.alb_arn
  rate_limit   = var.waf_rate_limit
  tags         = local.tags
}

# Subdomain A record pointing to ALB.
resource "aws_route53_record" "agent_a" {
  zone_id = module.dns.hosted_zone_id
  name    = "${var.subdomain}.${var.hosted_zone}"
  type    = "A"

  alias {
    name                   = module.alb.alb_dns_name
    zone_id                = module.alb.alb_zone_id
    evaluate_target_health = true
  }
}

# Subdomain AAAA (IPv6) record pointing to ALB.
resource "aws_route53_record" "agent_aaaa" {
  zone_id = module.dns.hosted_zone_id
  name    = "${var.subdomain}.${var.hosted_zone}"
  type    = "AAAA"

  alias {
    name                   = module.alb.alb_dns_name
    zone_id                = module.alb.alb_zone_id
    evaluate_target_health = true
  }
}

# =============================================================================
# Phase 6: Alarms
# =============================================================================

module "alarms" {
  source                  = "../../modules/alarms"
  project_name            = var.project_name
  environment             = local.env
  alb_arn_suffix          = module.alb.alb_arn_suffix
  target_group_arn_suffix = module.alb.target_group_arn_suffix
  ecs_cluster_name        = module.ecs.cluster_name
  ecs_service_name        = module.ecs_service.service_name
  alarm_email             = var.alarm_email
  tags                    = local.tags
}
