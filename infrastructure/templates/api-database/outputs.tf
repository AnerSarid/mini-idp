output "endpoint" {
  description = "Environment endpoint URL (friendly DNS if configured, ALB DNS otherwise)"
  value       = module.ecs_service.endpoint
}

output "cluster_arn" {
  description = "ECS cluster ARN"
  value       = module.ecs_service.cluster_arn
}

output "service_name" {
  description = "ECS service name"
  value       = module.ecs_service.service_name
}

output "log_group" {
  description = "CloudWatch log group name"
  value       = module.common.log_group_name
}

output "secret_arn" {
  description = "Secrets Manager secret ARN (app)"
  value       = module.common.secret_arn
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.networking.vpc_id
}

output "db_endpoint" {
  description = "RDS instance endpoint"
  value       = module.rds.db_instance_endpoint
}

output "db_address" {
  description = "RDS instance address"
  value       = module.rds.db_instance_address
}

output "db_port" {
  description = "RDS port"
  value       = module.rds.db_port
}

output "db_name" {
  description = "Database name"
  value       = module.rds.db_name
}

output "db_credentials_secret_arn" {
  description = "Secrets Manager ARN for DB credentials"
  value       = module.rds.db_credentials_secret_arn
}
