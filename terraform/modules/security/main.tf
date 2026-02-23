# =============================================================================
# SECURITY MODULE - Security Groups (Firewall Rules)
# =============================================================================
#
# Creates two security groups with a layered security model:
#
#   1. ALB Security Group
#      - Inbound: HTTP (80) and HTTPS (443) from allowed CIDRs
#      - Outbound: App port only to ECS tasks
#
#   2. ECS Security Group
#      - Inbound: App port from ALB security group ONLY
#      - Outbound: CIDR egress (for Bedrock API, DynamoDB, etc.)
#
# =============================================================================

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# =============================================================================
# Security Groups
# =============================================================================

resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "ALB security group"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-alb-sg"
  })

  # create_before_destroy prevents a window where no SG exists during replacement,
  # which would break the ALB or ECS service referencing it.
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "ecs" {
  name        = "${local.name_prefix}-ecs-sg"
  description = "ECS service security group"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-ecs-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# =============================================================================
# ALB Security Group Rules
# =============================================================================

# Conditional: when alb_ingress_cidrs is empty, no ingress rules are created,
# making the ALB internal-only (reachable only from within the VPC).
resource "aws_security_group_rule" "alb_ingress_http" {
  count             = length(var.alb_ingress_cidrs) > 0 ? 1 : 0
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = var.alb_ingress_cidrs
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from allowed CIDRs"
}

resource "aws_security_group_rule" "alb_ingress_https" {
  count             = length(var.alb_ingress_cidrs) > 0 ? 1 : 0
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = var.alb_ingress_cidrs
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from allowed CIDRs"
}

resource "aws_security_group_rule" "alb_egress_to_ecs" {
  type                     = "egress"
  from_port                = var.app_port
  to_port                  = var.app_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs.id
  security_group_id        = aws_security_group.alb.id
  description              = "App port to ECS tasks"
}

# =============================================================================
# ECS Security Group Rules
# =============================================================================

resource "aws_security_group_rule" "ecs_ingress_from_alb" {
  type                     = "ingress"
  from_port                = var.app_port
  to_port                  = var.app_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = aws_security_group.ecs.id
  description              = "App port from ALB"
}

# =============================================================================
# Mercure Security Group Rules (conditional on mercure_port > 0)
# =============================================================================

resource "aws_security_group_rule" "alb_egress_to_ecs_mercure" {
  count                    = var.mercure_port > 0 ? 1 : 0
  type                     = "egress"
  from_port                = var.mercure_port
  to_port                  = var.mercure_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs.id
  security_group_id        = aws_security_group.alb.id
  description              = "Mercure port to ECS tasks"
}

resource "aws_security_group_rule" "ecs_ingress_from_alb_mercure" {
  count                    = var.mercure_port > 0 ? 1 : 0
  type                     = "ingress"
  from_port                = var.mercure_port
  to_port                  = var.mercure_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = aws_security_group.ecs.id
  description              = "Mercure port from ALB"
}

# =============================================================================
# ECS Egress Rules
# =============================================================================

# One rule per CIDR so individual ranges can be added/removed without
# recreating the entire rule set.
resource "aws_security_group_rule" "ecs_egress_cidr" {
  for_each  = toset(var.ecs_egress_cidrs)
  type      = "egress"
  from_port = 0
  to_port   = 0
  # "-1" = all protocols; tasks need HTTPS (Bedrock, ECR), DNS, and NTP.
  protocol          = "-1"
  cidr_blocks       = [each.value]
  security_group_id = aws_security_group.ecs.id
  description       = "Egress to ${each.value}"
}
