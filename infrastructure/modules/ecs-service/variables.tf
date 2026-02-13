variable "environment_name" {
  description = "Name of the environment (e.g. dev, staging, prod)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment_name))
    error_message = "environment_name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "vpc_id" {
  description = "ID of the VPC where resources will be created"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for the ALB"
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_ids) >= 2
    error_message = "At least two public subnets are required for the ALB."
  }
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for the ECS tasks"
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_ids) >= 1
    error_message = "At least one private subnet is required for the ECS tasks."
  }
}

variable "task_execution_role_arn" {
  description = "ARN of the IAM role for ECS task execution (pulling images, writing logs)"
  type        = string
}

variable "task_role_arn" {
  description = "ARN of the IAM role for the running ECS task (application permissions)"
  type        = string
}

variable "log_group_name" {
  description = "Name of the CloudWatch Log Group for container logs"
  type        = string
}

variable "container_image" {
  description = "Docker image for the container (repository:tag)"
  type        = string
  default     = "nginx:alpine"
}

variable "container_port" {
  description = "Port the container listens on"
  type        = number
  default     = 80

  validation {
    condition     = var.container_port > 0 && var.container_port <= 65535
    error_message = "container_port must be between 1 and 65535."
  }
}

variable "cpu" {
  description = "CPU units for the Fargate task (256, 512, 1024, 2048, 4096)"
  type        = number
  default     = 256

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096], var.cpu)
    error_message = "cpu must be one of: 256, 512, 1024, 2048, 4096."
  }
}

variable "memory" {
  description = "Memory (MiB) for the Fargate task"
  type        = number
  default     = 512

  validation {
    condition     = var.memory >= 512 && var.memory <= 30720
    error_message = "memory must be between 512 and 30720 MiB."
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "aws_region" {
  description = "AWS region for CloudWatch log configuration"
  type        = string
  default     = "us-east-1"
}

variable "acm_certificate_arn" {
  description = "ARN of an ACM certificate for HTTPS. When provided, an HTTPS listener is created on port 443 and HTTP is redirected to HTTPS. When empty, only HTTP on port 80 is configured."
  type        = string
  default     = ""
}

variable "route53_zone_id" {
  description = "Route 53 hosted zone ID for creating a DNS CNAME record pointing to the ALB. When empty, no DNS record is created."
  type        = string
  default     = ""
}

variable "dns_name" {
  description = "Fully qualified domain name for this environment (e.g. preview-my-app.preview.anersarid.dev). Required when route53_zone_id is set."
  type        = string
  default     = ""
}
