# =============================================================================
# TERRAFORM BACKEND CONFIGURATION - Remote State Storage
# =============================================================================
#
# Values provided via backend.hcl using -backend-config flag.
# See backend.hcl.example for the template.
#
# =============================================================================

terraform {
  backend "s3" {}
}
