variable "name" {
  type = string
}

variable "cidr" {
  type = string
}

variable "tags" {
  type    = object({})
  default = {}
}

variable "availability_zones" {
  type = list(string)
}

variable "private_subnets" {
  type = list(string)
}

variable "public_subnets" {
  type = list(string)
}

variable "database_subnets" {
  type = list(string)
}

variable "root_domain" {
  type = string
}

variable "test_sub_domain" {
  type = string
}
