locals {

}

locals {
  s3_origin_id    = "myS3Origin"
  spa_error_codes = toset([403, 404])
  proxy_api_paths = ["/bff/*"]
  #  comments_api_paths = ["/comments-api/*"]
}

resource "aws_s3_bucket" "spa" {
  bucket = "${var.name}-spa"
}

resource "aws_s3_bucket_versioning" "spa" {
  bucket = aws_s3_bucket.spa.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "spa" {
  bucket = aws_s3_bucket.spa.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "spa" {
  bucket                  = aws_s3_bucket.spa.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "spa" {
  statement {
    sid = "PolicyForCloudFrontPrivateContent"
    principals {
      identifiers = [aws_cloudfront_origin_access_identity.spa.iam_arn]
      type        = "AWS"
    }
    actions   = ["s3:GetObject*"]
    resources = ["${aws_s3_bucket.spa.arn}/*"]
  }
}

resource "aws_s3_bucket_policy" "spa" {
  bucket = aws_s3_bucket.spa.id
  policy = data.aws_iam_policy_document.spa.json
}

locals {
  api_allowed_methods = [
    "DELETE",
    "GET",
    "HEAD",
    "OPTIONS",
    "PATCH",
    "POST",
    "PUT",
  ]
  api_forwarded_headers = [
    "Accept",
    "Accept-Language",
    "Authorization",
    "Origin",
    "Referer",
    "User-Agent",
  ]
  api_cached_methods = [
    "GET",
    "HEAD",
  ]
}

resource "aws_cloudfront_distribution" "cf" {
  origin {
    domain_name = aws_s3_bucket.spa.bucket_regional_domain_name
    origin_id   = local.s3_origin_id
    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.spa.cloudfront_access_identity_path
    }
  }

  dynamic "origin" {
    for_each = toset(["mockexchange-bff"])
    content {
      connection_attempts = 3
      connection_timeout  = 10
      domain_name         = "${origin.value}.${var.domain_name}"
      origin_id           = "${origin.value}.${var.domain_name}"
      custom_origin_config {
        http_port              = 80
        https_port             = 443
        origin_protocol_policy = "https-only"
        origin_ssl_protocols = [
          "TLSv1.2"
        ]
      }
    }
  }

  enabled             = true
  default_root_object = "index.html"
  default_cache_behavior {
    allowed_methods          = ["GET", "HEAD", "OPTIONS"]
    cached_methods           = ["GET", "HEAD", "OPTIONS"]
    target_origin_id         = local.s3_origin_id
    cache_policy_id          = "658327ea-f89d-4fab-a63d-7e88639e58f6" // CachingOptimized
    origin_request_policy_id = "88a5eaf4-2fd4-4709-b370-b4c650ea3fcf" // CORS-S3Origin
    viewer_protocol_policy   = "redirect-to-https"
  }

  dynamic "ordered_cache_behavior" {
    for_each = local.proxy_api_paths
    content {
      allowed_methods        = local.api_allowed_methods
      cached_methods         = local.api_cached_methods
      compress               = false
      default_ttl            = 0
      max_ttl                = 0
      min_ttl                = 0
      path_pattern           = ordered_cache_behavior.value
      smooth_streaming       = false
      target_origin_id       = "mockexchange-bff.${var.domain_name}"
      trusted_key_groups     = []
      trusted_signers        = []
      viewer_protocol_policy = "https-only"

      forwarded_values {
        headers                 = local.api_forwarded_headers
        query_string            = true
        query_string_cache_keys = []

        cookies {
          forward           = "all"
          whitelisted_names = []
        }
      }
    }
  }

  #  dynamic "ordered_cache_behavior" {
  #    for_each = local.comments_api_paths
  #    content {
  #      allowed_methods        = local.api_allowed_methods
  #      cached_methods         = local.api_cached_methods
  #      compress               = false
  #      default_ttl            = 0
  #      max_ttl                = 0
  #      min_ttl                = 0
  #      path_pattern           = ordered_cache_behavior.value
  #      smooth_streaming       = false
  #      target_origin_id       = "comments-api.${var.domain_name}"
  #      trusted_key_groups     = []
  #      trusted_signers        = []
  #      viewer_protocol_policy = "https-only"
  #
  #      forwarded_values {
  #        headers                 = local.api_forwarded_headers
  #        query_string            = true
  #        query_string_cache_keys = []
  #
  #        cookies {
  #          forward           = "all"
  #          whitelisted_names = []
  #        }
  #      }
  #    }
  #  }

  price_class = "PriceClass_100"
  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["US"]
    }
  }

  aliases = ["${var.name}.${var.domain_name}"]

  viewer_certificate {
    acm_certificate_arn = var.cert_arn
    ssl_support_method  = "sni-only"
  }

  dynamic "custom_error_response" {
    for_each = local.spa_error_codes
    content {
      error_code            = custom_error_response.value
      error_caching_min_ttl = 0
      response_page_path    = "/index.html"
      response_code         = 200
    }
  }

  web_acl_id = aws_wafv2_web_acl.cf.arn
}

resource "aws_cloudfront_origin_access_identity" "spa" {
  comment = "access-identity-spa-${var.name}"
}

resource "aws_route53_record" "cf" {
  name    = "${var.name}.${var.domain_name}"
  type    = "A"
  zone_id = var.zone_id

  alias {
    evaluate_target_health = false
    name                   = aws_cloudfront_distribution.cf.domain_name
    zone_id                = aws_cloudfront_distribution.cf.hosted_zone_id
  }
}

resource "aws_wafv2_ip_set" "home" {
  ip_address_version = "IPV4"
  name               = "home"
  scope              = "CLOUDFRONT"
  addresses = [
    "${var.allow_wan_ip}/32"
  ]
}

resource "aws_wafv2_web_acl" "cf" {
  name  = "${var.name}-cf-waf"
  scope = "CLOUDFRONT"

  default_action {
    block {}
  }
  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name}-cf-waf"
    sampled_requests_enabled   = false
  }
  rule {
    name     = "rate-limit"
    priority = 0

    action {
      block {}
    }

    statement {
      rate_based_statement {
        aggregate_key_type = "IP"
        limit              = 5000
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = false
      metric_name                = "rate-limit"
      sampled_requests_enabled   = false
    }
  }
  rule {
    name     = "allow-home-ip"
    priority = 1
    action {
      allow {}
    }
    statement {
      ip_set_reference_statement {
        arn = aws_wafv2_ip_set.home.arn
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = false
      metric_name                = "allow-home-ip"
      sampled_requests_enabled   = false
    }
  }
}
