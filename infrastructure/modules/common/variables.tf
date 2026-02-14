variable "environment_name" {
  description = "Name of the environment (e.g. dev, staging, prod). Used as a prefix for resource names."
  type        = string
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs. Valid values: 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653."
  type        = number
  default     = 3
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
