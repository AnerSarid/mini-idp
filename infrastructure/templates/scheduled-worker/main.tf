####################################################################
# Template: Scheduled Worker
# Provisions: ECS Scheduled Task, CloudWatch, optional S3 access
#
# Shared infrastructure (backend, provider, tags, networking, common)
# is provided by _base/*.tf — copied in at CI time.
####################################################################

locals {
  template_name = "scheduled-worker"
}

# --- Scheduled Task ---
module "scheduled_task" {
  source                 = "../../modules/scheduled-task"
  environment_name       = var.environment_name
  vpc_id                 = local.vpc_id
  private_subnet_ids     = local.private_subnet_ids
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
