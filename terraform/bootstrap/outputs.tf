# =============================================================================
# BOOTSTRAP OUTPUTS - Values Needed for Backend Configuration
# =============================================================================
#
# After running `terraform apply`, use these values in backend.hcl:
#   1. Copy environments/main/backend.hcl.example to backend.hcl
#   2. Paste these output values into backend.hcl
#   3. Run `terraform init -backend-config=backend.hcl` in environments/main/
#
# =============================================================================

output "state_bucket_name" {
  description = "S3 bucket name for Terraform state (use in backend.hcl)"
  value       = aws_s3_bucket.state.bucket
}

output "lock_table_name" {
  description = "DynamoDB table name for state locking (use in backend.hcl)"
  value       = aws_dynamodb_table.locks.name
}
