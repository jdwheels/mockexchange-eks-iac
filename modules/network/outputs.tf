output "private_subnets" {
  value = module.vpc.private_subnets
}

output "private_subnets_cidr_blocks" {
  value = module.vpc.private_subnets_cidr_blocks
}

output "public_subnets" {
  value = module.vpc.public_subnets
}

output "database_subnets" {
  value = module.vpc.database_subnets
}

output "database_subnet_group_name" {
  value = module.vpc.database_subnet_group_name
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "root_domain_name" {
  value = aws_route53_zone.root.name
}

output "test_zone_arn" {
  value = aws_route53_zone.test.arn
}

output "root_zone_arn" {
  value = aws_route53_zone.root.arn
}

output "root_domain_zone_id" {
  value = aws_route53_zone.root.zone_id
}

output "test_domain_name" {
  value = aws_route53_zone.test.name
}

output "test_zone_id" {
  value = aws_route53_zone.test.zone_id
}

output "test_domain_cert_arn" {
  value = aws_acm_certificate.test_wildcard.arn
}
