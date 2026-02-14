output "task_execution_role_arn" {
  description = "ARN of the ECS task execution role (used by the ECS agent)."
  value       = aws_iam_role.task_execution.arn
}

output "task_execution_role_name" {
  description = "Name of the ECS task execution role. Use to attach additional IAM policies."
  value       = aws_iam_role.task_execution.name
}

output "task_role_arn" {
  description = "ARN of the ECS task role (assumed by the running container)."
  value       = aws_iam_role.task.arn
}

output "task_role_name" {
  description = "Name of the ECS task role. Use this to attach additional IAM policies."
  value       = aws_iam_role.task.name
}

output "log_group_name" {
  description = "Name of the CloudWatch Log Group for ECS tasks."
  value       = aws_cloudwatch_log_group.this.name
}

output "log_group_arn" {
  description = "ARN of the CloudWatch Log Group."
  value       = aws_cloudwatch_log_group.this.arn
}

output "secret_arn" {
  description = "ARN of the Secrets Manager secret."
  value       = aws_secretsmanager_secret.this.arn
}

output "secret_name" {
  description = "Name of the Secrets Manager secret."
  value       = aws_secretsmanager_secret.this.name
}
