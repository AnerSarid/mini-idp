variable "preview_domain" {
  description = "Fully qualified domain for preview environments"
  type        = string
  default     = "preview.anersarid.com"
}

variable "preview_zone_id" {
  description = "Route 53 hosted zone ID for the preview subdomain (created outside Terraform, NS delegation managed in Cloudflare)"
  type        = string
  default     = "Z0154651Y1VFNGTT5STY"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}
