variable "name" {
  type = string
}

variable "zone_id" {
  type = string
}

variable "domain_name" {
  type = string
}

variable "cert_arn" {
  type = string
}

variable "allow_wan_ip" {
  type = string
  #  sensitive = true
}

variable "tags" {
  type    = object({})
  default = {}
}
