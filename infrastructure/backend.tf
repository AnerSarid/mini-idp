terraform {
  required_version = ">= 1.6.0"

  # Backend values are provided via -backend-config flags or backend.conf file.
  # Run: tofu init -backend-config=backend.conf
  backend "s3" {
    key = "global/terraform.tfstate"
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
      "idp:managed"  = "true"
      "idp:tool"     = "mini-idp"
      "cost-center"  = "engineering"
    }
  }
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}
