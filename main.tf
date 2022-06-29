terraform {
  backend "s3" {
    key = "mockexchange-eks-iac"
  }
  required_providers {
    kubectl = {
      source = "gavinbunney/kubectl"
    }
  }
}

locals {
  name        = "trivialepic"
  k8s_version = "1.22"
  region      = "us-east-1"
  domain      = "trivialepic.com"
  cidr = "10.0.0.0/16"

  tags = {
    Project = "mockexchange"
  }
}

module "network" {
  source = "./modules/network"

  name = local.name

  cidr               = local.cidr
  availability_zones = ["${local.region}a", "${local.region}b", "${local.region}c"]
  private_subnets    = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets     = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
  database_subnets   = ["10.0.7.0/24", "10.0.8.0/24", "10.0.9.0/24"]

  root_domain     = local.domain
  test_sub_domain = "test"

  tags = local.tags
}

resource "aws_kms_key" "eks" {
  description             = "EKS Secret Encryption Key"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = local.tags
}

module "database" {
  source = "./modules/database"

  vpc_id              = module.network.vpc_id
  subnet_group_name   = module.network.database_subnet_group_name
  allowed_cidr_blocks = module.network.private_subnets_cidr_blocks

  cluster_name  = local.name
  database_name = local.tags.Project
  username      = local.tags.Project

  kms_key_arn = aws_kms_key.eks.arn

  tags = local.tags
}

module "cluster" {
  source            = "./modules/cluster"
  cluster_name      = local.name
  default_namespace = local.tags.Project
  region            = local.region
  cidr = local.cidr

  allow_wan_ip = var.allow_wan_ip

  kms_arn = aws_kms_key.eks.arn

  vpc_id              = module.network.vpc_id
  vpc_private_subnets = module.network.private_subnets
  dns_zone_arns       = [module.network.root_zone_arn, module.network.test_zone_arn]
  domain_name         = module.network.test_domain_name
  zone_id             = module.network.test_zone_id

  tags = local.tags
}

provider "kubernetes" {
  config_context = module.cluster.cluster_name
}

provider "helm" {
  kubernetes {
    config_context = module.cluster.cluster_name
  }
}

provider "kubectl" {
  config_context = module.cluster.cluster_name
}

module "services" {
  source = "./modules/services"
  depends_on = [
    module.cluster,
    module.database
  ]
  cert_arn = module.network.test_domain_cert_arn

  allow_wan_ip = var.allow_wan_ip
  namespace    = local.tags.Project
  domain_name  = module.network.test_domain_name

  default_repo      = local.name
  populator_repo    = "${local.name}-populator"
  posts_api_repo    = "${local.tags.Project}-posts-api"
  comments_api_repo = "${local.tags.Project}-comments-api"
  bff_repo          = "${local.tags.Project}-bff"
  kms_key_arn       = aws_kms_key.eks.arn

  github_client_id     = var.github_client_id
  github_client_secret = var.github_client_secret

  database_type     = "postgresql"
  database_name     = module.database.name
  database_host     = module.database.endpoint
  database_port     = module.database.port
  database_username = module.database.username
  database_password = module.database.password

  oidc_provider     = module.cluster.oidc_provider
  oidc_provider_arn = module.cluster.oidc_provider_arn

  cluster_name = local.name

  tags = local.tags
}

module "ui" {
  source = "./modules/ui"

  name = local.tags.Project

  allow_wan_ip = var.allow_wan_ip

  cert_arn    = module.network.test_domain_cert_arn
  domain_name = module.network.test_domain_name
  zone_id     = module.network.test_zone_id

  tags = local.tags
}
