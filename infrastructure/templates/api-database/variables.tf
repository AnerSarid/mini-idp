####################################################################
# Template-specific variables for: api-database
#
# Shared variables (environment_name, owner, ttl, etc.) are in
# _base/variables.tf — copied in at CI time.
####################################################################

variable "container_image" {
  description = "Container image to deploy"
  type        = string
  default     = "nginx:alpine"
}

variable "container_port" {
  description = "Container port"
  type        = number
  default     = 80
}

variable "acm_certificate_arn" {
  description = "ARN of an ACM certificate for HTTPS. Leave empty for HTTP-only."
  type        = string
  default     = ""
}

variable "route53_zone_id" {
  description = "Route 53 hosted zone ID for DNS record. Leave empty to skip DNS."
  type        = string
  default     = ""
}

variable "preview_domain" {
  description = "Base domain for preview environments (e.g. preview.anersarid.dev). Used to construct {environment_name}.{preview_domain}."
  type        = string
  default     = ""
}

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "appdb"
}
