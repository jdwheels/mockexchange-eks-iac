variable "oidc_provider" {
  type = string
}

variable "oidc_provider_arn" {
  type = string
}

variable "dns_zone_arns" {
  type = list(string)
}

variable "domain_name" {
  type = string
}

variable "zone_id" {
  type = string
}

variable "namespace" {
  type = string
}
