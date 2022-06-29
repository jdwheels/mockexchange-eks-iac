locals {
  files_serviceaccount = "stackexchange-s3"
  repos                = toset([var.default_repo, var.populator_repo, var.comments_api_repo, var.posts_api_repo, var.bff_repo])
}

module "files" {
  source            = "./modules/files"
  bucket_name       = var.namespace
  kms_key_arn       = var.kms_key_arn
  oidc_provider     = var.oidc_provider
  oidc_provider_arn = var.oidc_provider_arn
  trust_subjects    = ["system:serviceaccount:${var.namespace}:${local.files_serviceaccount}"]
  tags              = var.tags
}

resource "kubernetes_service_account" "stackexchange_s3" {
  metadata {
    name      = local.files_serviceaccount
    namespace = var.namespace
    annotations = {
      "eks.amazonaws.com/role-arn" : module.files.s3_arn
    }
  }
}

resource "aws_ecr_repository" "repos" {
  for_each             = local.repos
  name                 = each.value
  image_tag_mutability = "MUTABLE"

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = var.kms_key_arn
  }
  tags = var.tags
}


resource "aws_wafv2_ip_set" "home_east1" {
  ip_address_version = "IPV4"
  name               = "home-us-east-1"
  scope              = "REGIONAL"
  addresses = [
    "${var.allow_wan_ip}/32"
  ]
}

locals {
  rate_limits = {
    "IP"           = 5000,
    "FORWARDED_IP" = 5000
  }
}

resource "aws_wafv2_web_acl" "api" {
  name  = "${var.namespace}-api-waf"
  scope = "REGIONAL"

  default_action {
    block {}
  }

  visibility_config {
    cloudwatch_metrics_enabled = false
    metric_name                = "mockexchange-api-waf"
    sampled_requests_enabled   = false
  }

  dynamic "rule" {
    for_each = local.rate_limits
    content {
      name     = "${lower(rule.key)}-rate-limit"
      priority = index(keys(local.rate_limits), rule.key)

      action {
        block {}
      }

      statement {
        rate_based_statement {
          aggregate_key_type = rule.key
          limit              = rule.value
          dynamic "forwarded_ip_config" {
            for_each = rule.key == "FORWARDED_IP" ? [rule.key] : []
            content {
              fallback_behavior = "MATCH"
              header_name       = "X-Forwarded-For"
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = false
        metric_name                = "rate-limit"
        sampled_requests_enabled   = false
      }
    }
  }

  rule {
    name     = "allow-home-ip"
    priority = 2
    action {
      allow {}
    }
    statement {
      or_statement {
        statement {
          ip_set_reference_statement {
            arn = aws_wafv2_ip_set.home_east1.arn
          }
        }
        statement {
          ip_set_reference_statement {
            arn = aws_wafv2_ip_set.home_east1.arn
            ip_set_forwarded_ip_config {
              fallback_behavior = "NO_MATCH"
              header_name       = "X-Forwarded-For"
              position          = "FIRST"
            }
          }
        }
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = false
      metric_name                = "allow-home-ip"
      sampled_requests_enabled   = false
    }
  }
}

locals {
  mockexchange_chart_dir = "../mockexchange/helm/charts/mockexchange"
  api_charts             = toset(["mockexchange-posts-api", "mockexchange-comments-api", "mockexchange-bff"])
}

locals {
  release_name = "mockexchange"
}

resource "random_password" "redis" {
  length = 10
}

#resource "aws_route53_health_check" "httpbin" {
#  fqdn = "httpbin.${var.domain_name}"
#  port = 443
#  type = "HTTPS"
#  resource_path = "/get"
#  failure_threshold = 1
#  request_interval = 30
#}

resource "helm_release" "istio_ingress" {
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "gateway"
  name       = "mockexchange-gateway"
  version    = "1.13.4"
  namespace  = var.namespace

  values = [
    yamlencode({
      replicaCount = 1
      autoscaling = {
        enabled = false
      }
      service = {
        // https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.4/guide/service/annotations/
        annotations = {
          "service.beta.kubernetes.io/aws-load-balancer-type"            = "external"
          "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip"
          "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internet-facing"
          "service.beta.kubernetes.io/aws-load-balancer-attributes"      = "load_balancing.cross_zone.enabled=true"
          #          "service.beta.kubernetes.io/load-balancer-source-ranges" = "${var.allow_wan_ip}/32"
          "service.beta.kubernetes.io/aws-load-balancer-ssl-cert"    = var.cert_arn
          "service.beta.kubernetes.io/aws-load-balancer-alpn-policy" = "HTTP2Preferred"
        }
        loadBalancerSourceRanges = ["${var.allow_wan_ip}/32"]
      }
    })
  ]
}

terraform {
  required_providers {
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "1.14.0"
    }
  }
}

locals {
  istio_services = toset(["mockexchange-bff", "comments-api"])
}

resource "kubectl_manifest" "bff_gateway" {
  depends_on = [helm_release.services]
  yaml_body = yamlencode({
    apiVersion = "networking.istio.io/v1beta1"
    kind       = "Gateway"
    metadata = {
      name      = "bff-gateway"
      namespace = var.namespace
      annotations = {
        #        "external-dns.alpha.kubernetes.io/aws-health-check-id" = aws_route53_health_check.httpbin.id
        #        "external-dns.alpha.kubernetes.io/ttl" = "60"
      }
    }
    spec = {
      selector = {
        app : helm_release.istio_ingress.name
        istio : helm_release.istio_ingress.name
      }
      servers = [
        {
          port = {
            number   = 443
            name     = "https"
            protocol = "HTTP"
          }
          hosts = [
            "mockexchange-bff.${var.domain_name}",
            "comments-api.${var.domain_name}"
          ]
        }
      ]
    }
  })
}

resource "kubectl_manifest" "bff_dr" {
  for_each   = local.istio_services
  depends_on = [helm_release.services]
  yaml_body = yamlencode({
    apiVersion = "networking.istio.io/v1beta1"
    kind       = "DestinationRule"
    metadata = {
      name      = each.value
      namespace = var.namespace
    },
    spec = {
      host = each.value
      subsets = [
        {
          name = "version-1"
          labels = {
            version = "1.16.0"
          }
        },
        #        {
        #          name = "version-2"
        #          labels = {
        #            version = "v2"
        #          }
        #        }
      ]
    }
  })
}

resource "kubectl_manifest" "bff_vs" {
  for_each   = local.istio_services
  depends_on = [helm_release.services]
  yaml_body = yamlencode({
    apiVersion = "networking.istio.io/v1beta1"
    kind       = "VirtualService"
    metadata = {
      name      = each.value
      namespace = var.namespace
    }
    spec = {
      hosts = [
        "${each.value}.${var.domain_name}"
      ]
      gateways = [
        kubectl_manifest.bff_gateway.name
      ]
      http = [
        {
          route = [
            {
              destination = {
                port = {
                  number = 80
                }
                host = each.value
              }
            }
          ]
        }
      ]
    }
  })
}

resource "kubectl_manifest" "rds_service_entry" {
  yaml_body = yamlencode({
    apiVersion = "networking.istio.io/v1beta1"
    kind       = "ServiceEntry"
    metadata = {
      name      = "mockexchange-rds"
      namespace = var.namespace
    }
    spec = {
      hosts = [
        var.database_host
      ]
      location = "MESH_EXTERNAL"
      ports = [
        {
          number   = var.database_port
          name     = var.database_type
          protocol = "TCP"
        }
      ]
      resolution = "DNS"
    }
  })
}

resource "helm_release" "services" {
  chart             = local.mockexchange_chart_dir
  dependency_update = true
  namespace         = var.namespace
  name              = local.release_name
  values = [
    file("${local.mockexchange_chart_dir}/values.eks.yaml"),

    yamlencode({
      database = {
        url      = "${var.database_type}://${var.database_host}:${var.database_port}/${var.database_name}"
        username = sensitive(var.database_username)
        password = sensitive(var.database_password)
      }

      redis = {
        url      = "${local.release_name}-bitnami-redis-master.${var.namespace}"
        password = sensitive(random_password.redis.result)
      }

      "bitnami-redis" = {
        global = {
          redis = {
            password = sensitive(random_password.redis.result)
          }
        }
        master = {
          disableCommands = []
        }
        replica = {
          replicaCount = 1
        }
      }

      "mockexchange-bff" = {
        oauth = {
          clientId     = sensitive(var.github_client_id)
          clientSecret = sensitive(var.github_client_secret)
          redirectUri  = "https://mockexchange.${var.domain_name}/bff/login/oauth2/code/github"
          ingress = {
            enabled = "false"
          }
        }
        extraEnv = [
          {
            name  = "BFFAPI_COOKIEDOMAIN"
            value = var.domain_name
          },
          {
            name  = "BFFAPI_LOGINSUCCESSURL"
            value = "https://mockexchange.${var.domain_name}"
          },
          {
            name  = "BFFAPI_POSTAPIBASEURL"
            value = "http://posts-api"
          },
          {
            name  = "MOCKEXCHANGEBFF_USERAPI_BASEURL"
            value = "http://posts-api"
          }
        ]
      }

      "mockexchange-comments-api" = {
        extraEnv = [
          {
            name  = "COMMENTSAPI_COOKIEDOMAIN"
            value = var.domain_name
          },
          {
            name  = "SPRING_FLYWAY_ENABLED"
            value = "false"
          }
        ]
        extraArgs = [
          "--server.servlet.context-path=/"
        ]
      }

      "mockexchange-posts-api" = {
        extraArgs = [
          "--spring.webflux.base-path=/"
        ]
      }
    })
  ]


  dynamic "set" {
    for_each = local.api_charts
    content {
      name  = "${set.value}.image.repository"
      value = aws_ecr_repository.repos[set.value].repository_url
    }
  }
  #  dynamic "set" {
  #    for_each = local.api_charts
  #    content {
  #      name  = "${set.value}.ingress.annotations.alb\\.ingress\\.kubernetes\\.io/wafv2-acl-arn"
  #      value = aws_wafv2_web_acl.api.arn
  #    }
  #  }
  dynamic "set" {
    for_each = local.api_charts
    content {
      name  = "${set.value}.ingress.domain"
      value = var.domain_name
    }
  }
}
