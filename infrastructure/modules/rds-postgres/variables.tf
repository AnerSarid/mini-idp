variable "environment_name" {
  description = "Name of the environment (e.g. dev, staging, prod). Used as a prefix for resource names."
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC where the RDS instance will be created."
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for the DB subnet group."
  type        = list(string)
}

variable "allowed_security_group_id" {
  description = "Security group ID allowed to connect to the database on port 5432."
  type        = string
}

variable "db_name" {
  description = "Name of the default database to create."
  type        = string
  default     = "appdb"
}

variable "instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t3.micro"
}

variable "allocated_storage" {
  description = "Allocated storage in GiB."
  type        = number
  default     = 20
}

variable "tags" {
  description = "Tags applied to every resource in this module."
  type        = map(string)
  default     = {}
}
