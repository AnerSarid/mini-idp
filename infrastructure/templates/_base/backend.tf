####################################################################
# Shared: Backend, Provider, Tags
#
# Copied into each template directory at CI time. Each template must
# define local.template_name (e.g. "api-service") in its own main.tf.
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
    "idp:environment" = var.environment_name
    "idp:template"    = local.template_name
    "idp:owner"       = var.owner
    "idp:created-at"  = var.created_at
    "idp:ttl"         = var.ttl
    "idp:expires-at"  = var.expires_at
    "cost-center"     = "engineering"
  }
}
