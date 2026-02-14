####################################################################
# Template 1: Stateless API Service
# Provisions: VPC, ALB, ECS Fargate service, CloudWatch, Secrets
####################################################################

terraform {
  required_version = ">= 1.6.0"

  backend "s3" {
    bucket         = "mini-idp-terraform-state"
    region         = "us-east-1"
    dynamodb_table = "mini-idp-terraform-locks"
    encrypt        = true
    # key is set dynamically via -backend-config
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
    "idp:template"     = "api-service"
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
  cpu                    = var.cpu
  memory                 = var.memory
  acm_certificate_arn    = var.acm_certificate_arn
  route53_zone_id        = var.route53_zone_id
  dns_name               = var.preview_domain != "" ? "${var.environment_name}.${var.preview_domain}" : ""
  aws_region             = var.aws_region
  environment_variables  = var.environment_variables
  secret_variables       = var.secret_variables
  tags                   = local.tags
}
