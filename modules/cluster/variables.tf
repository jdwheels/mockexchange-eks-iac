variable "cluster_name" {
  type = string
}

variable "k8s_version" {
  type    = string
  default = "1.22"
}

variable "default_namespace" {
  type = string
}

variable "region" {
  type = string
}

variable "allow_wan_ip" {
  type = string
}

variable "kms_arn" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "vpc_private_subnets" {
  type = list(string)
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

variable "tags" {
  type    = object({})
  default = {}
}

variable "cidr" {
  type = string
}
