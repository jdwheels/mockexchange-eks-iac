## https://docs.aws.amazon.com/eks/latest/userguide/aws-load-balancer-controller.html

data "http" "lb_policy_json" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/${var.aws_load_balancer_version}/docs/install/iam_policy.json"

  request_headers = {
    Accept = "application/json"
  }
}

resource "aws_iam_policy" "lb_policy" {
  name   = "AWSLoadBalancerControllerIAMPolicy"
  policy = data.http.lb_policy_json.body
}

data "aws_iam_policy_document" "lb" {
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
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
      variable = "${var.oidc_provider}:sub"
    }
  }
}

resource "aws_iam_role" "lb" {
  name               = "AmazonEKSLoadBalancerControllerRole"
  assume_role_policy = data.aws_iam_policy_document.lb.json
}

resource "aws_iam_role_policy_attachment" "lb" {
  policy_arn = aws_iam_policy.lb_policy.arn
  role       = aws_iam_role.lb.name
}

resource "kubernetes_service_account" "lb" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    labels = {
      "app.kubernetes.io/component" = "controller"
      "app.kubernetes.io/name"      = "aws-load-balancer-controller"
    }
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.lb.arn
    }
  }
}

resource "helm_release" "lb" {
  depends_on = [kubernetes_service_account.lb]
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"

  set {
    name  = "region"
    value = var.region
  }
  set {
    name  = "vpcId"
    value = var.vpc_id
  }
  set {
    name  = "clusterName"
    value = var.eks_cluster_id
  }
  set {
    name  = "serviceAccount.create"
    value = "false"
  }
  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }
}
