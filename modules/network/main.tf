module "vpc" {
  #  source = "../modules/external/vpc"
  source = "terraform-aws-modules/vpc/aws"
  name   = var.name
  cidr   = var.cidr

  azs              = var.availability_zones
  private_subnets  = var.private_subnets
  public_subnets   = var.public_subnets
  database_subnets = var.database_subnets

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  enable_flow_log                      = false
  create_flow_log_cloudwatch_iam_role  = true
  create_flow_log_cloudwatch_log_group = true

  public_subnet_tags = {
    "kubernetes.io/cluster/${var.name}" = "shared"
    "kubernetes.io/role/elb"            = 1
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${var.name}" = "shared"
    "kubernetes.io/role/internal-elb"   = 1
  }

  tags = var.tags
}

resource "aws_route53_zone" "root" {
  name = var.root_domain
}

resource "aws_route53_zone" "test" {
  name = "${var.test_sub_domain}.${var.root_domain}"

  tags = {
    Environment = "test"
  }
}

resource "aws_route53_record" "test_ns" {
  zone_id = aws_route53_zone.root.zone_id
  name    = aws_route53_zone.test.name
  type    = "NS"
  ttl     = "30"
  records = aws_route53_zone.test.name_servers
}

resource "aws_acm_certificate" "test_wildcard" {
  domain_name       = "*.${aws_route53_zone.test.name}"
  validation_method = "DNS"

  tags = {
    Environment = "test"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_route53_record" "test_wildcard" {
  for_each = {
    for dvo in aws_acm_certificate.test_wildcard.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value["name"]
  records         = [each.value["record"]]
  ttl             = 60
  type            = each.value["type"]
  zone_id         = aws_route53_zone.test.zone_id

  lifecycle {
    prevent_destroy = true
  }
}
