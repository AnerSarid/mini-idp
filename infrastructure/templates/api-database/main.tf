####################################################################
# Template 2: API + Database
# Provisions: Everything from Template 1 + RDS PostgreSQL
####################################################################

terraform {
  required_version = ">= 1.6.0"

  backend "s3" {
    bucket         = "mini-idp-terraform-state"
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
    tags = local.tags
  }
}

locals {
  tags = {
    "idp:managed"     = "true"
    "idp:environment"  = var.environment_name
    "idp:template"     = "api-database"
    "idp:owner"        = var.owner
    "idp:created-at"   = var.created_at
    "idp:ttl"          = var.ttl
    "idp:expires-at"   = var.expires_at
    "cost-center"      = "engineering"
  }
}

# --- Networking ---
module "networking" {
  source           = "../../modules/networking"
  environment_name = var.environment_name
  tags             = local.tags
}

# --- Common (IAM, Logs, Secrets) ---
module "common" {
  source           = "../../modules/common"
  environment_name = var.environment_name
  tags             = local.tags
}

# --- ECS Fargate Service + ALB ---
module "ecs_service" {
  source                 = "../../modules/ecs-service"
  environment_name       = var.environment_name
  vpc_id                 = module.networking.vpc_id
  public_subnet_ids      = module.networking.public_subnet_ids
  private_subnet_ids     = module.networking.private_subnet_ids
  task_execution_role_arn = module.common.task_execution_role_arn
  task_role_arn          = module.common.task_role_arn
  log_group_name         = module.common.log_group_name
  container_image        = var.container_image
  container_port         = var.container_port
  acm_certificate_arn    = var.acm_certificate_arn
  aws_region             = var.aws_region
  tags                   = local.tags
}

# --- RDS PostgreSQL ---
module "rds" {
  source                    = "../../modules/rds-postgres"
  environment_name          = var.environment_name
  vpc_id                    = module.networking.vpc_id
  private_subnet_ids        = module.networking.private_subnet_ids
  allowed_security_group_id = module.ecs_service.ecs_security_group_id
  db_name                   = var.db_name
  tags                      = local.tags
}
