output "repository_url" {
  description = "ECR repository URL"
  value       = aws_ecr_repository.preview.repository_url
}

output "repository_arn" {
  description = "ECR repository ARN"
  value       = aws_ecr_repository.preview.arn
}

output "repository_name" {
  description = "ECR repository name"
  value       = aws_ecr_repository.preview.name
}

output "pull_through_cache_prefix" {
  description = "ECR prefix for Docker Hub pull-through cache (e.g. docker-hub)"
  value       = aws_ecr_pull_through_cache_rule.docker_hub.ecr_repository_prefix
}
