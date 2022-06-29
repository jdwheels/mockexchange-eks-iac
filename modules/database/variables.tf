variable "cluster_name" {
  type = string
}

variable "database_name" {
  type = string
}

variable "username" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_group_name" {
  type = string
}

variable "allowed_cidr_blocks" {
  type = list(string)
}

variable "kms_key_arn" {
  type = string
}

variable "tags" {
  type    = object({})
  default = {}
}
