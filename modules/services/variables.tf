variable "allow_wan_ip" {
  type = string
  #  sensitive = true
}

variable "kms_key_arn" {
  type = string
}

variable "github_client_id" {
  type      = string
  sensitive = true
}

variable "github_client_secret" {
  type      = string
  sensitive = true
}

variable "domain_name" {
  type = string
}

variable "database_type" {
  type = string
}

variable "database_host" {
  type = string
}

variable "database_port" {
  type = number
}

variable "database_name" {
  type = string
}

variable "database_username" {
  type      = string
  sensitive = true
}

variable "database_password" {
  type      = string
  sensitive = true
}

variable "namespace" {
  type = string
}

variable "oidc_provider_arn" {
  type = string
}

variable "oidc_provider" {
  type = string
}

variable "default_repo" {
  type = string
}

variable "posts_api_repo" {
  type = string
}

variable "comments_api_repo" {
  type = string
}

variable "populator_repo" {
  type = string
}

variable "bff_repo" {
  type = string
}

variable "tags" {
  type    = object({})
  default = {}
}

variable "cert_arn" {
  type = string
}

variable "cluster_name" {
  type = string
}
