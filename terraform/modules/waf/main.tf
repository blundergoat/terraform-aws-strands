# =============================================================================
# WAF MODULE - AWS Web Application Firewall
# =============================================================================
#
# Protects the ALB against common web exploits:
#   - SQL injection, XSS, bad bots, known malicious IPs
#   - Rate limiting per IP
#   - Optional anonymous IP blocking
#
# =============================================================================

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

resource "aws_wafv2_web_acl" "main" {
  name        = "${local.name_prefix}-waf"
  description = "WAF for ${var.project_name} ${var.environment}"
  scope       = "REGIONAL"

  # Default allow: rules below block known-bad traffic; everything else passes.
  # This avoids accidentally blocking legitimate requests not yet categorized.
  default_action {
    allow {}
  }

  # Priority 1: OWASP top-10 protections (XSS, path traversal, etc.).
  # override_action { none {} } means "use the managed group's own actions"
  # (block/count); this is required for managed rule groups instead of action {}.
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"

        # Override specific rules to count-only mode for debugging false positives
        # without losing visibility. Add rule names to var.common_rules_excluded.
        dynamic "rule_action_override" {
          for_each = var.common_rules_excluded
          content {
            name = rule_action_override.value
            action_to_use {
              count {}
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-common-rules"
      sampled_requests_enabled   = true
    }
  }

  # Priority 2: Blocks requests with known-bad payloads (Log4Shell, etc.).
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  # Priority 3: SQL injection detection (DynamoDB backend, but defense-in-depth).
  rule {
    name     = "AWSManagedRulesSQLiRuleSet"
    priority = 3

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-sqli"
      sampled_requests_enabled   = true
    }
  }

  # Priority 4: Blocks IPs on Amazon's threat-intelligence reputation list.
  rule {
    name     = "AWSManagedRulesAmazonIpReputationList"
    priority = 4

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-ip-reputation"
      sampled_requests_enabled   = true
    }
  }

  # Priority 5: Per-IP rate limiting. Uses action {} (not override_action)
  # because this is a custom rule, not a managed rule group.
  rule {
    name     = "RateLimitRule"
    priority = 5

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  # Priority 6: Optional VPN/proxy/Tor blocking. Disabled by default because
  # it can block legitimate users behind corporate VPNs.
  dynamic "rule" {
    for_each = var.block_anonymous_ips ? [1] : []
    content {
      name     = "AWSManagedRulesAnonymousIpList"
      priority = 6

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          name        = "AWSManagedRulesAnonymousIpList"
          vendor_name = "AWS"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${local.name_prefix}-anonymous-ip"
        sampled_requests_enabled   = true
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name_prefix}-waf"
    sampled_requests_enabled   = true
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-waf"
  })
}

resource "aws_wafv2_web_acl_association" "alb" {
  count        = var.associate_alb ? 1 : 0
  resource_arn = var.alb_arn
  web_acl_arn  = aws_wafv2_web_acl.main.arn
}

resource "aws_wafv2_web_acl_logging_configuration" "main" {
  count                   = var.enable_logging ? 1 : 0
  log_destination_configs = [aws_cloudwatch_log_group.waf[0].arn]
  resource_arn            = aws_wafv2_web_acl.main.arn

  # Only log blocked requests to keep CloudWatch costs low. Allowed requests
  # are dropped from the log stream; inspect them via sampled_requests instead.
  logging_filter {
    default_behavior = "DROP"

    filter {
      behavior = "KEEP"

      condition {
        action_condition {
          action = "BLOCK"
        }
      }

      requirement = "MEETS_ANY"
    }
  }
}

resource "aws_cloudwatch_log_group" "waf" {
  count             = var.enable_logging ? 1 : 0
  name              = "aws-waf-logs-${local.name_prefix}"
  retention_in_days = var.log_retention_days

  tags = var.tags
}
