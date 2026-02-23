# =============================================================================
# ECR MODULE - Container Image Registry
# =============================================================================
#
# Creates an ECR repository for storing Docker images.
# Features: image scanning on push, AES-256 encryption, lifecycle policy.
#
# =============================================================================

resource "aws_ecr_repository" "this" {
  name                 = var.repository_name
  image_tag_mutability = var.image_tag_mutability

  # Scans every pushed image for CVEs via Amazon Inspector.
  image_scanning_configuration {
    scan_on_push = true
  }

  # AES256 uses the AWS-managed key at no extra cost. KMS would add per-request
  # charges with no meaningful security benefit for container images.
  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(var.tags, {
    Name = var.repository_name
  })
}

# Keep 10 images for rollback capability while bounding storage costs.
resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
