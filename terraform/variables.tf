variable "account" {
  type = string
}

variable "key_id" {
  type = string
}

variable "triton_url" {
  type = string
}

variable "consul_package" {
  type    = string
  default = "g4-highcpu-512M"
}
variable "vault_package" {
  type    = string
  default = "g4-highcpu-256M"
}
variable "vault_fe_package" {
  type    = string
  default = "g4-highcpu-128M"
}

variable "external_network" {
  type = string
}

variable "consul-agent-token" {
  type = map(any)
}

variable "vault-agent-token" {
  type = map(any)
}

variable "google_project" {
  type = string
}

variable "google_region" {
  type = string
}
