####################################################################
# Template: API + Database
# Provisions: ECS Fargate service + ALB + RDS PostgreSQL
#
# Shared infrastructure (backend, provider, tags, networking, common)
# is provided by _base/*.tf — copied in at CI time.
####################################################################

locals {
  template_name = "api-database"
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
