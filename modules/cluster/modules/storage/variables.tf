variable "oidc_provider" {
  type = string
}

variable "oidc_provider_arn" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "cidr_blocks" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}
