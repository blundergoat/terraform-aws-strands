# =============================================================================
# ALARMS MODULE - Monitoring and Alerting
# =============================================================================
#
# Creates CloudWatch alarms for ALB and ECS monitoring.
#
# =============================================================================

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# Customer-managed KMS key for SNS at-rest encryption (required for compliance
# frameworks that prohibit default AWS-managed keys on messaging services).
resource "aws_kms_key" "sns" {
  description             = "Customer-managed key for ${local.name_prefix} SNS topic encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-sns-kms"
  })
}

resource "aws_kms_alias" "sns" {
  name          = "alias/${local.name_prefix}-sns"
  target_key_id = aws_kms_key.sns.key_id
}

resource "aws_sns_topic" "alerts" {
  name              = "${local.name_prefix}-alerts"
  kms_master_key_id = aws_kms_key.sns.id

  tags = var.tags
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alarm_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# ALB 5XX errors alarm.
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${local.name_prefix}-alb-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  # Threshold of 10 allows transient 5xx errors (cold starts, brief blips)
  # without alerting. Sustained errors will breach quickly.
  threshold = 10

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.target_group_arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
  tags          = var.tags
}

# p95 latency catches tail-latency issues that averages would mask.
resource "aws_cloudwatch_metric_alarm" "alb_response_time" {
  alarm_name          = "${local.name_prefix}-alb-response-time"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  extended_statistic  = "p95"
  threshold           = 2

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.target_group_arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
  tags          = var.tags
}

# Fires when no tasks are running. Requires Container Insights enabled on the
# ECS cluster (see module.ecs enable_container_insights).
resource "aws_cloudwatch_metric_alarm" "ecs_running_tasks" {
  alarm_name          = "${local.name_prefix}-ecs-low-running-tasks"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "RunningTaskCount"
  namespace           = "ECS/ContainerInsights"
  period              = 300
  statistic           = "Average"
  threshold           = 1
  # Missing data means Container Insights stopped reporting — assume the worst.
  treat_missing_data = "breaching"

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = var.ecs_service_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
  tags          = var.tags
}
