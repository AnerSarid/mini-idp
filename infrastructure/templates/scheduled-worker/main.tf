####################################################################
# Template 3: Scheduled Worker
# Provisions: VPC, ECS Scheduled Task, CloudWatch, optional S3 access
####################################################################

terraform {
  required_version = ">= 1.6.0"

  # All backend values are provided via -backend-config flags from CI.
  # For local use: tofu init -backend-config=../../backend.conf -backend-config="key=environments/<name>/terraform.tfstate"
  backend "s3" {
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
    "idp:template"     = "scheduled-worker"
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
  source             = "../../modules/common"
  environment_name   = var.environment_name
  log_retention_days = var.log_retention_days
  tags               = local.tags
}

# --- Scheduled Task ---
module "scheduled_task" {
  source                 = "../../modules/scheduled-task"
  environment_name       = var.environment_name
  vpc_id                 = module.networking.vpc_id
  private_subnet_ids     = module.networking.private_subnet_ids
  task_execution_role_arn = module.common.task_execution_role_arn
  task_role_arn          = module.common.task_role_arn
  task_role_name         = module.common.task_role_name
  log_group_name         = module.common.log_group_name
  schedule_expression    = var.schedule_expression
  container_image        = var.container_image
  s3_bucket_arn          = var.s3_bucket_arn
  cpu                    = var.cpu
  memory                 = var.memory
  aws_region             = var.aws_region
  environment_variables  = var.environment_variables
  secret_variables       = var.secret_variables
  tags                   = local.tags
}
