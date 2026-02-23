# =============================================================================
# ECS MODULE - Container Orchestration
# =============================================================================
#
# Creates ECS cluster and task definition with agent + optional app sidecar.
# When app_image is provided, both containers run in the same task:
#   - Agent (port 8000): Python FastAPI backend
#   - App (port 8080): Web UI (calls agent at localhost:8000)
#
# =============================================================================

locals {
  agent_env = [
    for key, value in var.environment_variables : {
      name  = key
      value = value
    }
  ]

  app_env = [
    for key, value in var.app_environment_variables : {
      name  = key
      value = value
    }
  ]

  mercure_env = [
    for key, value in var.mercure_environment_variables : {
      name  = key
      value = value
    }
  ]

  agent_container = {
    name      = var.agent_container_name
    image     = var.agent_image
    essential = true
    portMappings = [
      {
        containerPort = var.agent_container_port
        hostPort      = var.agent_container_port
        protocol      = "tcp"
      }
    ]
    environment = local.agent_env
    secrets     = var.secrets
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = var.log_group_name_agent
        awslogs-region        = var.region
        awslogs-stream-prefix = "agent"
      }
    }
    healthCheck = {
      command  = var.health_check_command
      interval = 30
      timeout  = 5
      retries  = 3
      # Agent loads ML models on startup; 60s gives Bedrock SDK time to initialize.
      startPeriod = 60
    }
  }

  # Optional sidecar: when mercure_image is empty the entire block evaluates to
  # null, which concat() in container_definitions will skip.
  mercure_container = var.mercure_image != "" ? {
    name      = var.mercure_container_name
    image     = var.mercure_image
    essential = true
    portMappings = [
      {
        containerPort = var.mercure_container_port
        hostPort      = var.mercure_container_port
        protocol      = "tcp"
      }
    ]
    environment = local.mercure_env
    secrets     = var.mercure_secrets
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = var.log_group_name_mercure
        awslogs-region        = var.region
        awslogs-stream-prefix = "mercure"
      }
    }
    healthCheck = {
      command  = var.mercure_health_check_command
      interval = 30
      timeout  = 5
      retries  = 3
      # Mercure is a Go binary with sub-second startup; 15s is plenty.
      startPeriod = 15
    }
  } : null

  # App depends on agent (and Mercure when enabled) via ECS container dependency
  # ordering. ECS will not start the app until dependencies report HEALTHY.
  app_depends_on = concat(
    [
      {
        containerName = var.agent_container_name
        condition     = "HEALTHY"
      }
    ],
    local.mercure_container != null ? [
      {
        containerName = var.mercure_container_name
        condition     = "HEALTHY"
      }
    ] : []
  )

  app_container = var.app_image != "" ? {
    name      = var.app_container_name
    image     = var.app_image
    essential = true
    portMappings = [
      {
        containerPort = var.app_container_port
        hostPort      = var.app_container_port
        protocol      = "tcp"
      }
    ]
    environment = local.app_env
    secrets     = var.app_secrets
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = var.log_group_name_app
        awslogs-region        = var.region
        awslogs-stream-prefix = "app"
      }
    }
    healthCheck = {
      command  = var.app_health_check_command
      interval = 30
      timeout  = 5
      retries  = 3
      # App needs agent healthy first (see dependsOn); 30s covers its own init.
      startPeriod = 30
    }
    dependsOn = local.app_depends_on
  } : null

  container_definitions = concat(
    [local.agent_container],
    local.mercure_container != null ? [local.mercure_container] : [],
    local.app_container != null ? [local.app_container] : []
  )
}

# ECS cluster hosts Fargate tasks.
resource "aws_ecs_cluster" "this" {
  name = var.cluster_name

  setting {
    name  = "containerInsights"
    value = var.enable_container_insights ? "enabled" : "disabled"
  }
}

# Task definition for the service (agent + optional app sidecar).
resource "aws_ecs_task_definition" "agent" {
  family = var.agent_task_family
  # awsvpc gives each task its own ENI, required by Fargate.
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  # Fargate task-level cpu/memory must be strings; tostring() coerces the number.
  cpu                = tostring(var.cpu)
  memory             = tostring(var.memory)
  execution_role_arn = var.execution_role_arn
  task_role_arn      = var.task_role_arn

  container_definitions = jsonencode(local.container_definitions)
}
