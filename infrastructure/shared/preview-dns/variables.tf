variable "parent_domain" {
  description = "Parent domain name (e.g. anersarid.dev)"
  type        = string
  default     = "anersarid.dev"
}

variable "parent_zone_id" {
  description = "Route 53 hosted zone ID of the parent domain"
  type        = string
  default     = "Z059828920290Q58NVZR9"
}

variable "preview_subdomain" {
  description = "Subdomain prefix for preview environments (e.g. preview)"
  type        = string
  default     = "preview"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}
