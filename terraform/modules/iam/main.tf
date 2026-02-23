# =============================================================================
# IAM MODULE - Identity and Access Management Roles
# =============================================================================
#
# Creates two ECS roles:
#   1. Task Execution Role - pulls images, writes logs, fetches secrets
#   2. Task Role - Bedrock invoke, DynamoDB access (runtime permissions)
#
# Also creates GitHub Actions OIDC role for CI/CD (optional).
#
# =============================================================================

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# Trust policy for ECS tasks.
data "aws_iam_policy_document" "ecs_task_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# =============================================================================
# Task Execution Role (used by ECS Agent)
# =============================================================================

resource "aws_iam_role" "task_execution" {
  name               = "${local.name_prefix}-ecs-exec"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json

  tags = var.tags
}

# AWS managed policy covers ECR pull + CloudWatch Logs. Inline policy below
# adds secrets access that varies per deployment.
resource "aws_iam_role_policy_attachment" "task_execution_managed" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Dynamic statements so the policy is valid even with zero secrets/KMS keys.
data "aws_iam_policy_document" "task_execution_inline" {
  dynamic "statement" {
    for_each = length(var.secrets_arns) > 0 ? [1] : []
    content {
      effect    = "Allow"
      actions   = ["secretsmanager:GetSecretValue"]
      resources = var.secrets_arns
    }
  }

  dynamic "statement" {
    for_each = length(var.kms_key_arns) > 0 ? [1] : []
    content {
      effect    = "Allow"
      actions   = ["kms:Decrypt"]
      resources = var.kms_key_arns
    }
  }
}

resource "aws_iam_role_policy" "task_execution_inline" {
  name   = "${local.name_prefix}-ecs-exec-inline"
  role   = aws_iam_role.task_execution.id
  policy = data.aws_iam_policy_document.task_execution_inline.json
}

# =============================================================================
# Task Role (used by the application)
# =============================================================================

resource "aws_iam_role" "task" {
  name               = "${local.name_prefix}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json

  tags = var.tags
}

data "aws_iam_policy_document" "task_inline" {
  # Bedrock model invocation (always enabled)
  dynamic "statement" {
    for_each = var.enable_bedrock_access ? [1] : []
    content {
      sid    = "BedrockInvoke"
      effect = "Allow"
      actions = [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream"
      ]
      resources = length(var.bedrock_model_arns) > 0 ? var.bedrock_model_arns : [
        "arn:aws:bedrock:*::foundation-model/*",
        "arn:aws:bedrock:*:*:inference-profile/*"
      ]
    }
  }

  # Marketplace access lets the task accept Bedrock model license terms at
  # runtime. Resource "*" is required — Marketplace APIs don't support ARN scoping.
  dynamic "statement" {
    for_each = var.enable_bedrock_access ? [1] : []
    content {
      sid    = "MarketplaceModelAccess"
      effect = "Allow"
      actions = [
        "aws-marketplace:ViewSubscriptions",
        "aws-marketplace:Subscribe"
      ]
      resources = ["*"]
    }
  }

  # DynamoDB session table — Query but no Scan (least-privilege; the app only
  # looks up sessions by key, never full-table scans).
  dynamic "statement" {
    for_each = var.dynamodb_table_arn != "" ? [1] : []
    content {
      sid    = "DynamoDBSessionAccess"
      effect = "Allow"
      actions = [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem",
        "dynamodb:Query"
      ]
      resources = [var.dynamodb_table_arn]
    }
  }

  # Secrets Manager access (if ARNs provided)
  dynamic "statement" {
    for_each = length(var.secrets_arns) > 0 ? [1] : []
    content {
      effect    = "Allow"
      actions   = ["secretsmanager:GetSecretValue"]
      resources = var.secrets_arns
    }
  }
}

resource "aws_iam_role_policy" "task_inline" {
  name   = "${local.name_prefix}-ecs-task-inline"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task_inline.json
}

# =============================================================================
# GITHUB ACTIONS OIDC - CI/CD Role
# =============================================================================

resource "aws_iam_openid_connect_provider" "github" {
  count = var.github_repository != "" ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # AWS stopped validating GitHub OIDC thumbprints in 2023 (they use their own
  # root CA list), but the field is still required by the API.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = var.tags
}

resource "aws_iam_role" "github_actions" {
  count = var.github_repository != "" ? 1 : 0

  name = "${local.name_prefix}-github-actions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github[0].arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_repository}:*"
          }
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "github_actions_deploy" {
  count = var.github_repository != "" ? 1 : 0

  name = "deploy-policy"
  role = aws_iam_role.github_actions[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # ecr:GetAuthorizationToken does not support resource-level ARNs.
        Sid      = "ECRLogin"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Sid    = "ECRPush"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Resource = var.ecr_repository_arns
      },
      {
        # ECS task definition APIs don't support resource-level permissions.
        Sid    = "ECSTaskDefinitions"
        Effect = "Allow"
        Action = [
          "ecs:DescribeTaskDefinition",
          "ecs:RegisterTaskDefinition"
        ]
        Resource = "*"
      },
      {
        Sid    = "ECSServiceOperations"
        Effect = "Allow"
        Action = [
          "ecs:DescribeServices",
          "ecs:UpdateService",
          "ecs:DescribeTasks"
        ]
        Resource = [
          var.ecs_cluster_arn,
          var.ecs_service_arn,
          "arn:aws:ecs:*:*:task/${var.project_name}-cluster/*",
          "arn:aws:ecs:*:*:task-definition/${var.project_name}-*"
        ]
      },
      {
        # CI must pass both execution role (image pull/logs) and task role
        # (runtime permissions) when registering a new task definition.
        Sid    = "IAMPassRole"
        Effect = "Allow"
        Action = "iam:PassRole"
        Resource = [
          aws_iam_role.task_execution.arn,
          aws_iam_role.task.arn
        ]
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:GetLogEvents",
          "logs:FilterLogEvents"
        ]
        Resource = var.log_group_arns
      },
      {
        # DescribeTargetHealth does not support resource-level ARNs.
        Sid      = "ELBTargetHealth"
        Effect   = "Allow"
        Action   = "elasticloadbalancing:DescribeTargetHealth"
        Resource = "*"
      }
    ]
  })
}
