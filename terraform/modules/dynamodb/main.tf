# =============================================================================
# DYNAMODB MODULE - Session Persistence
# =============================================================================
#
# Creates a DynamoDB table for storing agent session history.
# Uses on-demand billing (PAY_PER_REQUEST) to avoid capacity planning.
# TTL automatically expires old sessions.
#
# =============================================================================

resource "aws_dynamodb_table" "sessions" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "session_id"

  attribute {
    name = "session_id"
    type = "S"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  tags = merge(var.tags, {
    Name = var.table_name
  })
}
