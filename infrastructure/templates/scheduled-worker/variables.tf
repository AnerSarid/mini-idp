####################################################################
# Template-specific variables for: scheduled-worker
#
# Shared variables (environment_name, owner, ttl, etc.) are in
# _base/shared-variables.tf — copied in at CI time.
####################################################################

variable "container_image" {
  description = "Container image for the scheduled task"
  type        = string
  default     = "alpine:latest"
}

variable "schedule_expression" {
  description = "CloudWatch Events schedule expression (e.g. 'rate(1 hour)' or 'cron(0 12 * * ? *)')"
  type        = string
  default     = "rate(1 hour)"
}

variable "s3_bucket_arn" {
  description = "S3 bucket ARN for read access (optional)"
  type        = string
  default     = ""
}
