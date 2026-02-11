################################################################################
# Data Sources
################################################################################

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  prefix = "idp-${var.environment_name}"
}

################################################################################
# ECS Task Execution Role
#
# Used by the ECS agent itself to pull images, push logs, and read secrets.
################################################################################

resource "aws_iam_role" "task_execution" {
  name = "${local.prefix}-ecs-task-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

# Attach the AWS-managed policy for baseline ECS execution permissions
# (ECR pull, CloudWatch Logs).
resource "aws_iam_role_policy_attachment" "task_execution_managed" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Allow the execution role to read the secret created by this module so ECS can
# inject secret values into containers at launch time.
resource "aws_iam_role_policy" "task_execution_secrets" {
  name = "${local.prefix}-ecs-exec-secrets"
  role = aws_iam_role.task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
        ]
        Resource = [
          aws_secretsmanager_secret.this.arn,
        ]
      }
    ]
  })
}

################################################################################
# ECS Task Role
#
# Assumed by the running container. Ships with no permissions — attach
# additional policies in the calling module via the exported role name.
################################################################################

resource "aws_iam_role" "task" {
  name = "${local.prefix}-ecs-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

################################################################################
# CloudWatch Log Group
################################################################################

resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${local.prefix}"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

################################################################################
# Secrets Manager Secret
#
# Created empty. Populate the secret value outside of Terraform (CLI, console,
# or a separate process) to avoid storing sensitive data in state.
################################################################################

resource "aws_secretsmanager_secret" "this" {
  name        = "${local.prefix}/app-secrets"
  description = "Application secrets for the ${local.prefix} environment."

  tags = var.tags
}
