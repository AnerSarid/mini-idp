####################################################################
# Shared Variables
#
# Copied into each template directory at CI time. Template-specific
# variables are defined in each template's own variables.tf.
####################################################################

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

variable "cpu" {
  description = "CPU units for the Fargate task (256, 512, 1024, 2048, 4096)"
  type        = number
  default     = 256
}

variable "memory" {
  description = "Memory in MiB for the Fargate task"
  type        = number
  default     = 512
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 3
}

variable "environment_variables" {
  description = "Plain environment variables for the container"
  type        = map(string)
  default     = {}
}

variable "secret_variables" {
  description = "Secrets Manager ARN references for the container"
  type        = map(string)
  default     = {}
}

variable "use_shared_networking" {
  description = "Use shared preview VPC instead of creating a per-environment VPC"
  type        = bool
  default     = false
}

variable "state_bucket" {
  description = "S3 bucket for Terraform state (needed for shared networking lookup)"
  type        = string
  default     = ""
}
