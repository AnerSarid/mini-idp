####################################################################
# Shared: Networking (per-env or shared VPC)
#
# Copied into each template directory at CI time. Provides local.vpc_id,
# local.public_subnet_ids, and local.private_subnet_ids.
####################################################################

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
