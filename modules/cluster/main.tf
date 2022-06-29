module "eks" {
  #  source = "./modules/external/eks"
  source = "terraform-aws-modules/eks/aws"
  #    source = "../../.terraform/modules/cluster.eks"

  cluster_name    = var.cluster_name
  cluster_version = var.k8s_version

  cluster_enabled_log_types = []

  cluster_addons = {
    kube-proxy = {}
    vpc-cni = {
      resolve_conflicts = "OVERWRITE"
    }
  }

  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = true
  cluster_endpoint_public_access_cidrs = [
    "${var.allow_wan_ip}/32"
  ]

  cluster_encryption_config = [{
    provider_key_arn = var.kms_arn
    resources        = ["secrets"]
  }]

  vpc_id     = var.vpc_id
  subnet_ids = var.vpc_private_subnets

  #  cluster_security_group_additional_rules = {
  #    egress_nodes_ephemeral_ports_tcp = {
  #      description                = "To node 1025-65535"
  #      protocol                   = "tcp"
  #      from_port                  = 1025
  #      to_port                    = 65535
  #      type                       = "egress"
  #      source_node_security_group = true
  #    }
  #  }
  #
  #  # Extend node-to-node security group rules
  #  node_security_group_additional_rules = {
  #    ingress_self_all = {
  #      description = "Node to node all ports/protocols"
  #      protocol    = "-1"
  #      from_port   = 0
  #      to_port     = 0
  #      type        = "ingress"
  #      self        = true
  #    }
  #    egress_all = {
  #      description      = "Node all egress"
  #      protocol         = "-1"
  #      from_port        = 0
  #      to_port          = 0
  #      type             = "egress"
  #      cidr_blocks      = ["0.0.0.0/0"]
  #      ipv6_cidr_blocks = ["::/0"]
  #    }
  #  }

  eks_managed_node_group_defaults = {
    ami_type       = "AL2_x86_64"
    instance_types = ["m6a.xlarge", "m6i.xlarge", "m5a.xlarge", "m5.xlarge"]
    capacity_type  = "SPOT"

    #    attach_cluster_primary_security_group = true
    #    vpc_security_group_ids                = [aws_security_group.additional.id]
  }

  #  eks_managed_node_groups = {
  #    blue = {}
  #    green = {
  #      min_size = 2
  #      max_size = 4
  #      desired_size = 2
  #      instance_types = ["m6a.large"]
  #      capacity_type = "SPOT"
  #    }
  #    update_config = {
  #      max_unavailable_percentage = 50
  #    }
  #  }
  eks_managed_node_groups = {
    bottlerocket_default = {
      # By default, the module creates a launch template to ensure tags are propagated to instances, etc.,
      # so we need to disable it to use the default template provided by the AWS EKS managed node group service
      create_launch_template = false
      launch_template_name   = ""
      ami_type               = "BOTTLEROCKET_x86_64"
      platform               = "bottlerocket"
      min_size               = 1
      max_size               = 4
      desired_size           = 3
    }
  }

  fargate_profiles = {
    default = {
      name = "default"
      selectors = [
        {
          namespace = "${var.default_namespace}-fg"
        }
      ]
    }
    #    coredns = {
    #      name = "coredns",
    #      selectors = [
    #        {
    #          namespace = "kube-system"
    #          labels = {
    #            k8s-app : "kube-dns"
    #          }
    #        }
    #      ]
    #    },
    #    lb = {
    #      name = "lb",
    #      selectors = [
    #        {
    #          namespace = "kube-system"
    #          labels = {
    #            "app.kubernetes.io/name" : "aws-load-balancer-controller"
    #          }
    #        }
    #      ]
    #    }
    #    cert_manager = {
    #      name = "cert-manager",
    #      selectors = [
    #        {
    #          namespace = "cert-manager"
    #        }
    #      ]
    #    }
  }
}

resource "aws_eks_addon" "coredns" {
  depends_on        = [module.eks]
  addon_name        = "coredns"
  cluster_name      = module.eks.cluster_id
  resolve_conflicts = "OVERWRITE"
  addon_version     = "v1.8.7-eksbuild.1"
  lifecycle { ignore_changes = [tags] }
}

resource "null_resource" "update_kubeconfig" {
  depends_on = [module.eks]

  provisioner "local-exec" {
    command = "aws eks update-kubeconfig --name ${var.cluster_name} --alias ${var.cluster_name} && kubectl config use-context ${var.cluster_name}"
  }
}

module "logging" {
  source                    = "./modules/logging"
  fargate_profile_role_name = module.eks.fargate_profiles["default"]["iam_role_name"]
  region                    = var.region
}

module "load_balancer" {
  source                    = "./modules/load-balancer"
  region                    = var.region
  vpc_id                    = var.vpc_id
  eks_cluster_id            = module.eks.cluster_id
  oidc_provider             = module.eks.oidc_provider
  oidc_provider_arn         = module.eks.oidc_provider_arn
  aws_load_balancer_version = "v2.4.1"
}

module "external_dns" {
  source            = "./modules/external-dns"
  namespace         = var.default_namespace
  oidc_provider     = module.eks.oidc_provider
  oidc_provider_arn = module.eks.oidc_provider_arn
  dns_zone_arns     = var.dns_zone_arns
  domain_name       = var.domain_name
  zone_id           = var.zone_id
}

module "istio" {
  source = "./modules/istio"
}

resource "kubernetes_namespace" "default" {
  depends_on = [
    module.istio
  ]
  metadata {
    name = var.default_namespace
    labels = {
      "istio-injection" = "enabled"
    }
  }
}

module "storage" {
  source = "./modules/storage"
  oidc_provider = module.eks.oidc_provider
  oidc_provider_arn = module.eks.oidc_provider_arn
  cidr_blocks = var.cidr
  vpc_id = var.vpc_id
  subnet_ids = var.vpc_private_subnets
}
