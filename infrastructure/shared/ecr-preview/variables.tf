variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "dockerhub_username" {
  description = "Docker Hub username for pull-through cache authentication"
  type        = string
  default     = ""
}

variable "dockerhub_access_token" {
  description = "Docker Hub access token (PAT) for pull-through cache authentication"
  type        = string
  sensitive   = true
  default     = ""
}
