output "endpoint" {
  description = "ALB DNS endpoint"
  value       = module.ecs_service.alb_dns_name
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
  description = "Secrets Manager secret ARN"
  value       = module.common.secret_arn
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.networking.vpc_id
}
