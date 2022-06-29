locals {
  name = "stackexchange"
}

resource "aws_s3_bucket" "files" {
  bucket = var.bucket_name
  tags   = var.tags
}

resource "aws_s3_bucket_server_side_encryption_configuration" "enc" {
  bucket = aws_s3_bucket.files.bucket

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.kms_key_arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_iam_policy" "stackexchange_s3" {
  name = "${local.name}-upload"
  policy = jsonencode({
    Version : "2012-10-17",
    Statement = [
      {
        Effect : "Allow",
        Action : [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucketMultipartUploads",
          "s3:AbortMultipartUpload",
          "s3:DeleteObject",
          "s3:PutObjectAcl",
          "s3:ListMultipartUploadParts",
          "s3:ListBucket"
        ],
        Resource : [
          aws_s3_bucket.files.arn,
          "${aws_s3_bucket.files.arn}/*"
        ]
      },
      {
        Effect : "Allow",
        Action : [
          "kms:GenerateDataKey",
          "kms:Decrypt"
        ],
        Resource : var.kms_key_arn
      }
    ]
  })
}

data "aws_iam_policy_document" "files_trust" {
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
      values   = var.trust_subjects
      variable = "${var.oidc_provider}:sub"
    }
  }
}

resource "aws_iam_role" "files_s3" {
  name               = "${local.name}_s3"
  assume_role_policy = data.aws_iam_policy_document.files_trust.json
}

resource "aws_iam_role_policy_attachment" "stackexchange_s3" {
  policy_arn = aws_iam_policy.stackexchange_s3.arn
  role       = aws_iam_role.files_s3.name
}
