terraform {
  required_version = ">= 1.6.0"

  # Backend values are provided via -backend-config flags or backend.conf file.
  # Run: tofu init -backend-config=../../backend.conf
  backend "s3" {
    key = "shared/ecr-preview/terraform.tfstate"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      "idp:managed" = "true"
      "idp:tool"    = "mini-idp"
      "idp:purpose" = "ecr-preview"
      "cost-center" = "engineering"
    }
  }
}

################################################################################
# ECR Repository for Preview Environment Images
################################################################################

resource "aws_ecr_repository" "preview" {
  name                 = var.ecr_repo_name
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = false
  }

  tags = {
    Name = var.ecr_repo_name
  }
}

################################################################################
# ECR Pull-Through Cache — Docker Hub
#
# Caches Docker Hub images locally in this ECR registry to avoid rate limits.
# Images pulled as: <account>.dkr.ecr.<region>.amazonaws.com/docker-hub/<image>
# e.g. .../docker-hub/library/node:20-alpine
#
# Docker Hub requires authentication. Credentials are stored in a Secrets
# Manager secret with the required "ecr-pullthroughcache/" prefix.
# To enable: set dockerhub_username and dockerhub_access_token variables.
################################################################################

resource "aws_secretsmanager_secret" "dockerhub" {
  count                   = var.dockerhub_username != "" ? 1 : 0
  name                    = "ecr-pullthroughcache/docker-hub"
  description             = "Docker Hub credentials for ECR pull-through cache"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "dockerhub" {
  count     = var.dockerhub_username != "" ? 1 : 0
  secret_id = aws_secretsmanager_secret.dockerhub[0].id
  secret_string = jsonencode({
    username    = var.dockerhub_username
    accessToken = var.dockerhub_access_token
  })
}

resource "aws_ecr_pull_through_cache_rule" "docker_hub" {
  count                 = var.dockerhub_username != "" ? 1 : 0
  ecr_repository_prefix = "docker-hub"
  upstream_registry_url = "registry-1.docker.io"
  credential_arn        = aws_secretsmanager_secret.dockerhub[0].arn
}

resource "aws_ecr_lifecycle_policy" "preview" {
  repository = aws_ecr_repository.preview.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Keep only the last 50 tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["preview-"]
          countType     = "imageCountMoreThan"
          countNumber   = 50
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
