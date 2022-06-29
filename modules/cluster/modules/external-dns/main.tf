## https://aws.amazon.com/premiumsupport/knowledge-center/eks-set-up-externaldns/

data "aws_iam_policy_document" "external_dns" {
  statement {
    actions = [
      "route53:ChangeResourceRecordSets"
    ]
    resources = var.dns_zone_arns
  }
  statement {
    actions = [
      "route53:ListHostedZones",
      "route53:ListResourceRecordSets"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "external_dns" {
  policy = data.aws_iam_policy_document.external_dns.json
}

locals {
  external_dns_sa = "external-dns"
}

data "aws_iam_policy_document" "external_dns_trust" {
  statement {
    principals {
      identifiers = [var.oidc_provider_arn]
      type        = "Federated"
    }
    actions = ["sts:AssumeRoleWithWebIdentity"]
    condition {
      test     = "StringEquals"
      values   = ["sts.amazonaws.com"]
      variable = "${var.oidc_provider}:aud"
    }
    condition {
      test     = "StringEquals"
      values   = ["system:serviceaccount:${var.namespace}:${local.external_dns_sa}"]
      variable = "${var.oidc_provider}:sub"
    }
  }
}

resource "aws_iam_role" "external_dns" {
  name               = local.external_dns_sa
  assume_role_policy = data.aws_iam_policy_document.external_dns_trust.json
}

resource "aws_iam_role_policy_attachment" "external_dns" {
  policy_arn = aws_iam_policy.external_dns.arn
  role       = aws_iam_role.external_dns.name
}

resource "helm_release" "external_dns" {
  depends_on = [aws_iam_role.external_dns]
  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  name       = "external-dns"
  namespace  = var.namespace

  values = [
    yamlencode({
      serviceAccount = {
        name = local.external_dns_sa
        annotations = {
          "eks.amazonaws.com/role-arn" = aws_iam_role.external_dns.arn
        }
      }
      rbac = {
        additionalPermissions = [
          {
            apiGroups = ["networking.istio.io"]
            resources = ["gateways", "virtualservices"]
            verbs     = ["get", "watch", "list"]
          }
        ]
      }
      sources = [
        "service",
        "ingress",
        "istio-gateway"
      ]
      domainFilters = [var.domain_name]
      policy        = "sync"
      txtOwnerId    = "/hostedzone/${var.zone_id}"
      extraArgs     = ["--aws-zone-type=public"]
    })
  ]
}
