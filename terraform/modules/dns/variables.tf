# =============================================================================
# DNS MODULE VARIABLES
# =============================================================================

variable "domain_name" {
  description = "Root domain name (e.g., 'example.com')"
  type        = string
}

variable "subdomain" {
  description = "Subdomain for cert scope. When set, cert covers only this subdomain (not root or www)."
  type        = string
  default     = ""
}

variable "create_hosted_zone" {
  description = "If true, create a Route53 hosted zone; otherwise use hosted_zone_id"
  type        = bool
  default     = true
}

variable "hosted_zone_id" {
  description = "Existing hosted zone ID to reuse when not creating a new one"
  type        = string
  default     = ""
}

variable "additional_subdomains" {
  description = "Additional subdomains to include in ACM certificate (e.g., ['agent'])"
  type        = list(string)
  default     = []
}

variable "tags" {
  type    = map(string)
  default = {}
}
