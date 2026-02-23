# =============================================================================
# BOOTSTRAP MODULE - Terraform Remote State Infrastructure
# =============================================================================
#
# Creates the foundational infrastructure for storing Terraform state remotely.
# Run this ONCE before setting up your main infrastructure.
#
# This module creates:
#   - S3 Bucket: Stores the terraform.tfstate file with versioning & encryption
#   - DynamoDB Table: Provides state locking to prevent concurrent modifications
#
# HOW TO USE:
#   1. cd terraform/bootstrap
#   2. terraform init
#   3. terraform apply
#   4. Note the outputs - you'll need them for environments/main/backend.hcl
#
# IMPORTANT: This module uses LOCAL state (no backend block) because it creates
# the backend infrastructure itself. Keep the bootstrap state file safe!
#
# =============================================================================

provider "aws" {
  region = var.aws_region
}

# Customer-managed KMS key for encrypting Terraform state.
resource "aws_kms_key" "state" {
  description         = "KMS key for Terraform state (${var.environment})"
  enable_key_rotation = true

  tags = {
    Project   = var.project_name
    Env       = var.environment
    ManagedBy = "terraform"
  }
}

resource "aws_kms_alias" "state" {
  name          = "alias/${var.project_name}-${var.environment}-tfstate"
  target_key_id = aws_kms_key.state.key_id
}

# S3 bucket for Terraform state.
resource "aws_s3_bucket" "state" {
  bucket = var.state_bucket_name

  tags = {
    Project   = var.project_name
    Env       = var.environment
    ManagedBy = "terraform"
  }
}

# Enable versioning to keep historical state files.
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Encrypt state files at rest.
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.state.arn
    }
  }
}

# Block all public access to the state bucket.
resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# DynamoDB table for state locking (prevents concurrent applies).
resource "aws_dynamodb_table" "locks" {
  name         = var.lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Project   = var.project_name
    Env       = var.environment
    ManagedBy = "terraform"
  }
}
