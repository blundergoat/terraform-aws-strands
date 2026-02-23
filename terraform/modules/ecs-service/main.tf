# =============================================================================
# ECS SERVICE MODULE - Long-Running Container Deployment
# =============================================================================
#
# Maintains desired number of tasks running behind the ALB.
# Rolling deployments with automatic rollback via circuit breaker.
# Optional autoscaling based on CPU and memory utilization.
#
# =============================================================================

# Build the list of target groups dynamically so the service registers with
# both the main app TG and the Mercure TG (when enabled) in a single resource.
locals {
  load_balancers = concat(
    [
      {
        target_group_arn = var.target_group_arn
        container_name   = var.container_name
        container_port   = var.container_port
      }
    ],
    var.mercure_target_group_arn != "" ? [
      {
        target_group_arn = var.mercure_target_group_arn
        container_name   = var.mercure_container_name
        container_port   = var.mercure_container_port
      }
    ] : []
  )
}

resource "aws_ecs_service" "this" {
  name            = var.service_name
  cluster         = var.cluster_arn
  task_definition = var.task_definition_arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = var.subnet_ids
    security_groups = var.security_group_ids
    # Tasks run in private subnets; outbound traffic goes through NAT Gateway.
    assign_public_ip = false
  }

  dynamic "load_balancer" {
    for_each = local.load_balancers
    content {
      target_group_arn = load_balancer.value.target_group_arn
      container_name   = load_balancer.value.container_name
      container_port   = load_balancer.value.container_port
    }
  }

  # Circuit breaker auto-rolls back if new tasks fail to stabilize,
  # preventing a bad deploy from draining all healthy tasks.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  enable_ecs_managed_tags = true
  propagate_tags          = "SERVICE"

  tags = var.tags

  lifecycle {
    # Autoscaling changes desired_count at runtime; ignoring it prevents
    # Terraform from resetting the count back on every apply.
    ignore_changes = [desired_count]
  }
}

# =============================================================================
# Autoscaling (optional)
# =============================================================================

resource "aws_appautoscaling_target" "ecs" {
  count        = var.enable_autoscaling ? 1 : 0
  max_capacity = var.autoscaling_max
  min_capacity = var.autoscaling_min
  # AppAutoScaling expects "service/<cluster>/<service>"; split extracts the
  # cluster name from the full ARN (arn:aws:ecs:region:account:cluster/<name>).
  resource_id        = "service/${split("/", var.cluster_arn)[1]}/${aws_ecs_service.this.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# CPU scaling at 50%: LLM inference is CPU-intensive; scale early to keep
# response latency low before tasks saturate.
resource "aws_appautoscaling_policy" "cpu" {
  count              = var.enable_autoscaling ? 1 : 0
  name               = "${var.service_name}-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs[0].resource_id
  scalable_dimension = aws_appautoscaling_target.ecs[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = var.cpu_target_value
  }
}

# Memory scaling at 60%: higher threshold than CPU because memory usage is
# steadier; scaling too early wastes capacity.
resource "aws_appautoscaling_policy" "memory" {
  count              = var.enable_autoscaling ? 1 : 0
  name               = "${var.service_name}-memory-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs[0].resource_id
  scalable_dimension = aws_appautoscaling_target.ecs[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
    target_value = var.memory_target_value
  }
}
