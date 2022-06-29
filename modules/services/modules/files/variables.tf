variable "kms_key_arn" {
  type = string
}

variable "oidc_provider_arn" {
  type = string
}

variable "oidc_provider" {
  type = string
}

variable "bucket_name" {
  type = string
}

variable "tags" {
  type    = object({})
  default = {}
}

variable "trust_subjects" {
  type = list(string)
}
