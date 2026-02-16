output "task_definition_arn" {
  description = "ECS task definition ARN"
  value       = module.scheduled_task.task_definition_arn
}

output "event_rule_name" {
  description = "CloudWatch Event Rule name"
  value       = module.scheduled_task.event_rule_name
}

output "event_rule_arn" {
  description = "CloudWatch Event Rule ARN"
  value       = module.scheduled_task.event_rule_arn
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
  value       = local.vpc_id
}
