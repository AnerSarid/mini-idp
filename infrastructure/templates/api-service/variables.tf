variable "environment_name" {
  description = "Name of the environment"
  type        = string
}

variable "owner" {
  description = "Owner email"
  type        = string
}

variable "ttl" {
  description = "Time to live (e.g. 7d)"
  type        = string
  default     = "7d"
}

variable "created_at" {
  description = "Creation timestamp (ISO 8601)"
  type        = string
}

variable "expires_at" {
  description = "Expiration timestamp (ISO 8601)"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

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
