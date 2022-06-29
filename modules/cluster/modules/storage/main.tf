data http "ebs_policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-ebs-csi-driver/v1.7.0/docs/example-iam-policy.json"
}

resource "aws_iam_policy" "ebs" {
  policy = data.http.ebs_policy.body
  name = "AmazonEKS_EBS_CSI_Driver_Policy"
}

data "aws_iam_policy_document" "ebs" {
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
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
      variable = "${var.oidc_provider}:sub"
    }
  }
}

resource "aws_iam_role" "ebs" {
  name               = "AmazonEKS_EBS_CSI_DriverRole"
  assume_role_policy = data.aws_iam_policy_document.ebs.json
}

resource "aws_iam_role_policy_attachment" "ebs" {
  policy_arn = aws_iam_policy.ebs.arn
  role       = aws_iam_role.ebs.name
}

#######################################################################################################################

data http "efs_policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-efs-csi-driver/v1.4.0/docs/iam-policy-example.json"
}

resource "aws_iam_policy" "efs" {
  policy = data.http.efs_policy.body
  name = "AmazonEKS_EFS_CSI_Driver_Policy"
}


data "aws_iam_policy_document" "efs" {
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
      values   = ["system:serviceaccount:kube-system:efs-csi-controller-sa"]
      variable = "${var.oidc_provider}:sub"
    }
  }
}

resource "aws_iam_role" "efs" {
  name               = "AmazonEKS_EFS_CSI_DriverRole"
  assume_role_policy = data.aws_iam_policy_document.efs.json
}

resource "aws_iam_role_policy_attachment" "efs" {
  policy_arn = aws_iam_policy.efs.arn
  role       = aws_iam_role.efs.name
}

resource "kubernetes_service_account" "efs" {
  metadata {
    name      = "efs-csi-controller-sa"
    namespace = "kube-system"
    labels = {
      "app.kubernetes.io/name"      = "aws-efs-csi-driver"
    }
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.efs.arn
    }
  }
}

resource "aws_security_group" "efs" {
  description = "efs-test-sg"
  name = "efs-sg"
  vpc_id = var.vpc_id
}

resource "aws_security_group_rule" "efs" {
  from_port         = 2049
  protocol          = "tcp"
  security_group_id = aws_security_group.efs.id
  to_port           = 2049
  type              = "ingress"
  cidr_blocks = [var.cidr_blocks]
}

resource "aws_efs_file_system" "efs" {
  creation_token = "eks-efs"
}

resource "aws_efs_mount_target" "efs" {
  for_each = toset(var.subnet_ids)
  file_system_id = aws_efs_file_system.efs.id
  subnet_id      = each.value
  security_groups = [aws_security_group.efs.id]
}
