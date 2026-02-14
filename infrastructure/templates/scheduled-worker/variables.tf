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
