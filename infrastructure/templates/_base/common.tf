####################################################################
# Shared: Common (IAM, Logs, Secrets)
#
# Copied into each template directory at CI time.
####################################################################

module "common" {
  source             = "../../modules/common"
  environment_name   = var.environment_name
  log_retention_days = var.log_retention_days
  tags               = local.tags
}
