####################################################################
# Template: Stateless API Service
# Provisions: ECS Fargate service + ALB
#
# Shared infrastructure (backend, provider, tags, networking, common)
# is provided by _base/*.tf — copied in at CI time.
####################################################################

locals {
  template_name = "api-service"
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
  environment_variables  = var.environment_variables
  secret_variables       = var.secret_variables
  tags                   = local.tags
}
