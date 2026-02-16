terraform {
  required_version = ">= 1.6.0"

  # Backend values are provided via -backend-config flags or backend.conf file.
  # Run: tofu init -backend-config=../../backend.conf
  backend "s3" {
    key = "shared/preview-networking/terraform.tfstate"
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
    tags = {
      "idp:managed" = "true"
      "idp:tool"    = "mini-idp"
      "idp:purpose" = "preview-networking"
      "cost-center" = "engineering"
    }
  }
}

module "networking" {
  source           = "../../modules/networking"
  environment_name = "shared-preview"
  vpc_cidr         = var.vpc_cidr
}
