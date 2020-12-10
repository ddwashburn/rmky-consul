terraform {
  required_providers {
    triton = {
      source  = "joyent/triton"
      version = "~> 0.8.1"
    }

    consul = {
      source  = "hashicorp/consul"
      version = "2.10.1"
    }

    google = {
      source  = "hashicorp/google"
      version = "3.46.0"
    }

    vault = {
      source  = "hashicorp/vault"
      version = "2.15.0"
    }
  }

  required_version = "~> 0.13.0"
}

provider "triton" {
  account                  = var.account
  key_id                   = var.key_id
  url                      = var.triton_url
  insecure_skip_tls_verify = false
}

provider "consul" {
  #  address    = "consul.rmky.org:8500"
  datacenter = "cle-1"
}

provider "vault" {
  address = "https://vault.rmky.org"
}

provider "google" {
  project = var.google_project
  region  = var.google_region
}
