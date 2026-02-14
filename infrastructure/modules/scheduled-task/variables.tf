variable "environment_name" {
  description = "Name of the environment (e.g. dev, staging, prod). Used as a prefix for resource names."
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC where the task will run."
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for the Fargate task network configuration."
  type        = list(string)
}

variable "task_execution_role_arn" {
  description = "ARN of the ECS task execution role (used by the ECS agent to pull images and push logs)."
  type        = string
}

variable "task_role_arn" {
  description = "ARN of the ECS task role (assumed by the running container)."
  type        = string
}

variable "task_role_name" {
  description = "Name of the ECS task role. Used to attach the S3 read policy."
  type        = string
}

variable "log_group_name" {
  description = "Name of the CloudWatch Log Group for container logs."
  type        = string
}

variable "schedule_expression" {
  description = "CloudWatch Events schedule expression (e.g. \"rate(1 hour)\" or \"cron(0 12 * * ? *)\")."
  type        = string
}

variable "container_image" {
  description = "Docker image to run as the scheduled task."
  type        = string
  default     = "alpine:latest"
}

variable "s3_bucket_arn" {
  description = "ARN of the S3 bucket to grant read access to. Leave empty to skip the policy."
  type        = string
  default     = ""
}

variable "cpu" {
  description = "CPU units for the Fargate task (256 = 0.25 vCPU)."
  type        = number
  default     = 256
}

variable "memory" {
  description = "Memory in MiB for the Fargate task."
  type        = number
  default     = 512
}

variable "aws_region" {
  description = "AWS region for CloudWatch log configuration."
  type        = string
  default     = "us-east-1"
}

variable "environment_variables" {
  description = "Plain environment variables to inject into the container"
  type        = map(string)
  default     = {}
}

variable "secret_variables" {
  description = "Secrets Manager references to inject as container env vars. Value format: full ARN or ARN:json-key:version-stage:version-id"
  type        = map(string)
  default     = {}
}

variable "container_insights" {
  description = "Whether to enable CloudWatch Container Insights on the ECS cluster (\"enabled\" or \"disabled\")"
  type        = string
  default     = "enabled"

  validation {
    condition     = contains(["enabled", "disabled"], var.container_insights)
    error_message = "container_insights must be \"enabled\" or \"disabled\"."
  }
}

variable "tags" {
  description = "Tags applied to every resource in this module."
  type        = map(string)
  default     = {}
}
