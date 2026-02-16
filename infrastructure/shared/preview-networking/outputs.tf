output "vpc_id" {
  description = "ID of the shared preview VPC"
  value       = module.networking.vpc_id
}

output "public_subnet_ids" {
  description = "IDs of the shared public subnets"
  value       = module.networking.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs of the shared private subnets"
  value       = module.networking.private_subnet_ids
}

output "vpc_cidr_block" {
  description = "CIDR block of the shared VPC"
  value       = module.networking.vpc_cidr_block
}
