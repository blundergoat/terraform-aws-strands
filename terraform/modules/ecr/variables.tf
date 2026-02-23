# =============================================================================
# ECR MODULE VARIABLES
# =============================================================================

variable "repository_name" {
  description = "Name of the ECR repository for Docker images"
  type        = string
}

variable "image_tag_mutability" {
  type    = string
  default = "IMMUTABLE"
}

variable "tags" {
  type    = map(string)
  default = {}
}
