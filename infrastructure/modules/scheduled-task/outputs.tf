output "task_definition_arn" {
  description = "ARN of the ECS task definition for the scheduled task."
  value       = aws_ecs_task_definition.this.arn
}

output "event_rule_arn" {
  description = "ARN of the CloudWatch Event Rule."
  value       = aws_cloudwatch_event_rule.this.arn
}

output "event_rule_name" {
  description = "Name of the CloudWatch Event Rule."
  value       = aws_cloudwatch_event_rule.this.name
}

output "task_security_group_id" {
  description = "ID of the security group attached to the scheduled task."
  value       = aws_security_group.task.id
}
