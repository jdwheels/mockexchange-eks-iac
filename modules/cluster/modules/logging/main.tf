## https://docs.aws.amazon.com/eks/latest/userguide/fargate-logging.html

resource "aws_iam_policy" "logging" {
  name = "eks-fargate-logging-policy"
  policy = jsonencode({
    Version : "2012-10-17",
    Statement = [
      {
        Effect : "Allow",
        Action : [
          "logs:CreateLogStream",
          "logs:CreateLogGroup",
          "logs:DescribeLogStreams",
          "logs:PutLogEvents"
        ],
        Resource : "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "fargate_logging" {
  policy_arn = aws_iam_policy.logging.arn
  role       = var.fargate_profile_role_name
}

resource "kubernetes_namespace" "aws-observability" {
  metadata {
    name = "aws-observability"
    labels = {
      aws-observability : "enabled"
    }
  }
}

resource "kubernetes_config_map" "aws-logging" {
  depends_on = [aws_iam_role_policy_attachment.fargate_logging]

  metadata {
    namespace = kubernetes_namespace.aws-observability.id
    name      = "aws-logging"
  }
  data = {
    "output.conf" = <<-EOT
    [OUTPUT]
      Name cloudwatch_logs
      Match   *
      region ${var.region}
      log_group_name fluent-bit-cloudwatch
      log_stream_prefix from-fluent-bit-
      auto_create_group true
      log_key log
    EOT

    "parsers.conf" = <<-EOT
    [PARSER]
      Name crio
      Format Regex
      Regex ^(?<time>[^ ]+) (?<stream>stdout|stderr) (?<logtag>P|F) (?<log>.*)$
      Time_Key    time
      Time_Format %Y-%m-%dT%H:%M:%S.%L%z
    EOT

    "filters.conf" = <<-EOT
    [FILTER]
      Name parser
      Match *
      Key_name log
      Parser crio
    EOT
  }
}
