####################################################################
# Template 2: API + Database
# Provisions: Everything from Template 1 + RDS PostgreSQL
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
    "idp:template"     = "api-database"
    "idp:owner"        = var.owner
    "idp:created-at"   = var.created_at
    "idp:ttl"          = var.ttl
    "idp:expires-at"   = var.expires_at
    "cost-center"      = "engineering"
  }
}

# --- Networking (per-env or shared) ---
module "networking" {
  count            = var.use_shared_networking ? 0 : 1
  source           = "../../modules/networking"
  environment_name = var.environment_name
  tags             = local.tags
}

data "terraform_remote_state" "shared_networking" {
  count   = var.use_shared_networking ? 1 : 0
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "shared/preview-networking/terraform.tfstate"
    region = var.aws_region
  }
}

locals {
  vpc_id             = var.use_shared_networking ? data.terraform_remote_state.shared_networking[0].outputs.vpc_id : module.networking[0].vpc_id
  public_subnet_ids  = var.use_shared_networking ? data.terraform_remote_state.shared_networking[0].outputs.public_subnet_ids : module.networking[0].public_subnet_ids
  private_subnet_ids = var.use_shared_networking ? data.terraform_remote_state.shared_networking[0].outputs.private_subnet_ids : module.networking[0].private_subnet_ids
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
  vpc_id                 = local.vpc_id
  public_subnet_ids      = local.public_subnet_ids
  private_subnet_ids     = local.private_subnet_ids
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
  tags                   = local.tags

  # Auto-inject DB connection info as env vars; merge with user-provided vars
  environment_variables = merge({
    DB_HOST = module.rds.db_instance_address
    DB_PORT = tostring(module.rds.db_port)
    DB_NAME = module.rds.db_name
  }, var.environment_variables)

  secret_variables = merge({
    DB_USER     = "${module.rds.db_credentials_secret_arn}:username::"
    DB_PASSWORD = "${module.rds.db_credentials_secret_arn}:password::"
  }, var.secret_variables)
}

# --- Allow execution role to read DB credentials secret ---
resource "aws_iam_role_policy" "exec_read_db_secret" {
  name = "idp-${var.environment_name}-exec-db-secret"
  role = module.common.task_execution_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [module.rds.db_credentials_secret_arn]
      }
    ]
  })
}

# --- RDS PostgreSQL ---
module "rds" {
  source                    = "../../modules/rds-postgres"
  environment_name          = var.environment_name
  vpc_id                    = local.vpc_id
  private_subnet_ids        = local.private_subnet_ids
  allowed_security_group_id = module.ecs_service.ecs_security_group_id
  db_name                   = var.db_name
  tags                      = local.tags
}
