################################################################################
# Locals
################################################################################

locals {
  prefix = var.environment_name

  common_tags = merge(var.tags, {
    "idp:module" = "scheduled-task"
  })
}

################################################################################
# ECS Cluster
################################################################################

resource "aws_ecs_cluster" "this" {
  name = "${local.prefix}-scheduled-cluster"

  setting {
    name  = "containerInsights"
    value = "disabled"
  }

  tags = merge(local.common_tags, {
    Name = "${local.prefix}-scheduled-cluster"
  })
}

################################################################################
# Security Group (egress-only)
################################################################################

resource "aws_security_group" "task" {
  name        = "${local.prefix}-scheduled-task-sg"
  description = "Security group for the scheduled Fargate task. Egress only."
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name = "${local.prefix}-scheduled-task-sg"
  })
}

resource "aws_security_group_rule" "task_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.task.id
  description       = "Allow all outbound"
}

################################################################################
# S3 Read Policy (optional)
################################################################################

resource "aws_iam_role_policy" "s3_read" {
  count = var.s3_bucket_arn != "" ? 1 : 0

  name = "${local.prefix}-scheduled-task-s3-read"
  role = var.task_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
        ]
        Resource = [
          var.s3_bucket_arn,
          "${var.s3_bucket_arn}/*",
        ]
      }
    ]
  })
}

################################################################################
# ECS Task Definition (Fargate)
################################################################################

resource "aws_ecs_task_definition" "this" {
  family                   = "${local.prefix}-scheduled-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = var.task_execution_role_arn
  task_role_arn            = var.task_role_arn

  container_definitions = jsonencode([
    {
      name      = "scheduled-task"
      image     = var.container_image
      essential = true

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = var.log_group_name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "scheduled"
        }
      }
    }
  ])

  tags = merge(local.common_tags, {
    Name = "${local.prefix}-scheduled-task"
  })
}

################################################################################
# IAM Role for CloudWatch Events to run ECS tasks
################################################################################

resource "aws_iam_role" "events" {
  name = "${local.prefix}-events-ecs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "events_run_task" {
  name = "${local.prefix}-events-run-task"
  role = aws_iam_role.events.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecs:RunTask",
        ]
        Resource = [
          aws_ecs_task_definition.this.arn,
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole",
        ]
        Resource = [
          var.task_execution_role_arn,
          var.task_role_arn,
        ]
      }
    ]
  })
}

################################################################################
# CloudWatch Event Rule & Target
################################################################################

resource "aws_cloudwatch_event_rule" "this" {
  name                = "${local.prefix}-scheduled-task"
  description         = "Triggers the ${local.prefix} scheduled ECS task."
  schedule_expression = var.schedule_expression

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "this" {
  rule     = aws_cloudwatch_event_rule.this.name
  arn      = aws_ecs_cluster.this.arn
  role_arn = aws_iam_role.events.arn

  ecs_target {
    task_count          = 1
    task_definition_arn = aws_ecs_task_definition.this.arn
    launch_type         = "FARGATE"

    network_configuration {
      subnets          = var.private_subnet_ids
      security_groups  = [aws_security_group.task.id]
      assign_public_ip = false
    }
  }
}
