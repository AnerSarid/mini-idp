output "preview_zone_id" {
  description = "Route 53 hosted zone ID for preview environments"
  value       = aws_route53_zone.preview.zone_id
}

output "preview_zone_name" {
  description = "Fully qualified domain for preview environments"
  value       = aws_route53_zone.preview.name
}

output "acm_certificate_arn" {
  description = "ARN of the wildcard ACM certificate for *.preview.anersarid.dev"
  value       = aws_acm_certificate.wildcard.arn
}

output "name_servers" {
  description = "Name servers for the preview subdomain zone"
  value       = aws_route53_zone.preview.name_servers
}
