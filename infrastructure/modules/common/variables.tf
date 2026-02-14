variable "environment_name" {
  description = "Name of the environment (e.g. dev, staging, prod). Used as a prefix for resource names."
  type        = string
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs."
  type        = number
  default     = 7
}

variable "additional_secret_arns" {
  description = "Additional Secrets Manager ARNs the execution role should be allowed to read (e.g. DB credentials)."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to every resource in this module."
  type        = map(string)
  default     = {}
}
