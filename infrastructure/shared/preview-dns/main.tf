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
# Subdomain Hosted Zone
################################################################################

resource "aws_route53_zone" "preview" {
  name    = "${var.preview_subdomain}.${var.parent_domain}"
  comment = "Hosted zone for mini-idp preview environments"
}

################################################################################
# NS Delegation from parent zone
################################################################################

resource "aws_route53_record" "delegation" {
  zone_id = var.parent_zone_id
  name    = "${var.preview_subdomain}.${var.parent_domain}"
  type    = "NS"
  ttl     = 300
  records = aws_route53_zone.preview.name_servers
}

################################################################################
# Wildcard ACM Certificate + DNS Validation
################################################################################

resource "aws_acm_certificate" "wildcard" {
  domain_name       = "*.${var.preview_subdomain}.${var.parent_domain}"
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
