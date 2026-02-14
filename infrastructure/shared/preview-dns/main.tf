terraform {
  required_version = ">= 1.6.0"

  backend "s3" {
    bucket         = "mini-idp-terraform-state"
    key            = "shared/preview-dns/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "mini-idp-terraform-locks"
    encrypt        = true
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
      "idp:purpose" = "preview-dns"
      "cost-center" = "engineering"
    }
  }
}

################################################################################
# Preview Zone (managed outside Terraform — NS delegation is in Cloudflare)
# Imported via: tofu import aws_route53_zone.preview Z0154651Y1VFNGTT5STY
################################################################################

resource "aws_route53_zone" "preview" {
  name    = var.preview_domain
  comment = "mini-idp preview environments"
}

################################################################################
# Wildcard ACM Certificate + DNS Validation
################################################################################

resource "aws_acm_certificate" "wildcard" {
  domain_name       = "*.${var.preview_domain}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.wildcard.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id         = aws_route53_zone.preview.zone_id
  name            = each.value.name
  type            = each.value.type
  ttl             = 60
  records         = [each.value.record]
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "wildcard" {
  certificate_arn         = aws_acm_certificate.wildcard.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}
