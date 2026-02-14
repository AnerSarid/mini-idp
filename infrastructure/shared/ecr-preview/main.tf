terraform {
  required_version = ">= 1.6.0"

  backend "s3" {
    bucket         = "mini-idp-terraform-state"
    key            = "shared/ecr-preview/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "mini-idp-terraform-locks"
    encrypt        = true
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
  name                 = "mini-idp-preview"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = false
  }

  tags = {
    Name = "mini-idp-preview"
  }
}

################################################################################
# ECR Pull-Through Cache — Docker Hub
#
# Caches Docker Hub images locally in this ECR registry to avoid rate limits.
# Images pulled as: <account>.dkr.ecr.<region>.amazonaws.com/docker-hub/<image>
# e.g. .../docker-hub/library/node:20-alpine
################################################################################

resource "aws_ecr_pull_through_cache_rule" "docker_hub" {
  ecr_repository_prefix = "docker-hub"
  upstream_registry_url = "registry-1.docker.io"
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
