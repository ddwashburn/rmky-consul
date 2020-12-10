data "triton_image" "hashicorp-base-64" {
  name        = "hashicorp-base-64"
  most_recent = true
}

data "triton_image" "vault-server" {
  name    = "vault-server"
  version = "1.5.5-202010300102"
}

data "triton_image" "vault-frontend" {
  name        = "vault-frontend"
  most_recent = true
}

resource "triton_firewall_rule" "vault-ssh" {
  description = "Allow SSH to all Vault systems"
  rule        = "FROM any TO tag \"vault\" ALLOW tcp PORT 22"
  enabled     = true
}

resource "triton_firewall_rule" "vault-tcp" {
  description = "Allow Vault API traffic"
  rule        = "FROM tag \"vault\" TO tag \"vault\" ALLOW tcp (PORT 8200 AND PORT 8201)"
  enabled     = true
}

resource "triton_firewall_rule" "vault-frontend-tcp" {
  description = "Allow HTTP and HTTPS traffic to the Vault frontend"
  rule        = "FROM any TO tag \"haproxy\" ALLOW tcp (PORT 80 AND PORT 443 AND PORT 1936)"
  enabled     = true
}

resource "consul_acl_policy" "vault-server" {
  name        = "vault-server"
  description = "Vault Server Policy"
  datacenters = [data.triton_datacenter.current.name]
  rules       = <<-RULE
    "key_prefix" "vault/" {
        policy = "write"
    }
    "node_prefix" "" {
        policy = "write"
    }
    "service" "vault" {
        policy = "write"
    }
    "agent_prefix" "" {
        policy = "write"
    }
    "session_prefix" "" {
        policy = "write"
    }
  RULE
}

resource "consul_acl_policy" "vault-node" {
  count       = 2
  name        = "vault-node-${count.index}"
  description = "Vault Node ${count.index} Policy"
  datacenters = [data.triton_datacenter.current.name]
  rules       = <<-RULE
    "node" "vault-${count.index}" {
        policy = "write"
    }
  RULE
}

resource "consul_acl_token" "vault-server" {
  count       = 2
  description = "vault-${count.index} node policy"
  policies    = [consul_acl_policy.vault-server.name, consul_acl_policy.vault-node[count.index].name]
  #local       = false
}

data "consul_acl_token_secret_id" "vault-server" {
  count       = 2
  accessor_id = consul_acl_token.vault-server[count.index].id
}

resource "consul_acl_token" "vault-storage-backend" {
  description = "Vault Storage Backend"
  policies    = [consul_acl_policy.vault-server.name]
  #local       = false
}

data "consul_acl_token_secret_id" "vault-storage-backend" {
  accessor_id = consul_acl_token.vault-storage-backend.id
}

resource "triton_machine" "vault-server" {
  count   = 2
  name    = "vault-${count.index}"
  package = var.vault_package
  image   = data.triton_image.vault-server.id

  firewall_enabled = true

  affinity = [
    "instance!=~vault-0",
    "instance!=~vault-1",
    "instance!=~vault-2",
  ]

  tags = {
    consul = "client"
    vault  = "server"
  }

  cns {
    services = ["vault"]
  }

  metadata = {
    "vault-server"        = "true",
    "vault-api-addr"      = "https://vault.rmky.org"
    "vault-storage-token" = data.consul_acl_token_secret_id.vault-storage-backend.secret_id
    "consul-join-addr"    = local.consul-join-addr
    "consul-gossip-key"   = local.consul-gossip-key
    "consul-agent-ca"     = local.consul-agent-ca
    "consul-agent-token"  = data.consul_acl_token_secret_id.vault-server[count.index].id
    "consul-server-cert"  = file("../ca/${data.triton_datacenter.current.name}-client-consul-${count.index}.pem")
    "consul-server-key"   = file("../ca/${data.triton_datacenter.current.name}-client-consul-${count.index}-key.pem")
    "consul-metadata" = jsonencode({
      "vault-version" = split("-", data.triton_image.vault-server.version)[0]
      "package-name"  = var.vault_package,
      "image-name"    = data.triton_image.consul-server.name,
      "image-version" = data.triton_image.consul-server.version,
    })
  }

  networks = [data.triton_network.external.id]

}

resource "consul_acl_policy" "vault-fe" {
  count       = 1
  name        = "vault-fe-${count.index}"
  description = "Vault Frontend ${count.index} Policy"
  datacenters = [data.triton_datacenter.current.name]
  rules       = <<-RULE
    "node" "vault-fe-${count.index}" {
        policy = "write"
    }
    "service_prefix" "" {
        policy = "read"
    }
    "node_prefix" "" {
        policy = "read"
    }
  RULE
}

resource "consul_acl_token" "vault-fe" {
  count       = 1
  description = "vault-fe-${count.index} node policy"
  policies    = [consul_acl_policy.vault-fe[count.index].name]
}

data "consul_acl_token_secret_id" "vault-fe" {
  count       = 1
  accessor_id = consul_acl_token.vault-fe[count.index].id
}

resource "triton_machine" "vault-fe" {
  count   = 1
  name    = "vault-fe-${count.index}"
  package = var.vault_fe_package
  image   = data.triton_image.vault-frontend.id

  firewall_enabled = true

  affinity = [
    "instance!=~vault-0",
    "instance!=~vault-1",
  ]

  tags = {
    consul  = "client"
    vault   = "client"
    haproxy = "server"
  }

  cns {
    services = ["vault-fe", "consul-fe"]
  }

  metadata = {
    "vault-server"       = "false",
    "vault-api-addr"     = "https://vault.rmky.org"
    "consul-join-addr"   = local.consul-join-addr
    "consul-gossip-key"  = local.consul-gossip-key
    "consul-agent-ca"    = local.consul-agent-ca
    "consul-agent-token" = data.consul_acl_token_secret_id.vault-fe[count.index].id
    "consul-server-cert" = file("../ca/${data.triton_datacenter.current.name}-client-consul-0.pem")
    "consul-server-key"  = file("../ca/${data.triton_datacenter.current.name}-client-consul-0-key.pem")
  }

  networks = [data.triton_network.external.id]
}

# Cloud KMS Auto-Unseal
resource "google_service_account" "unseal" {
  account_id  = "unseal"
  description = "Vault auto-unseal"
}

resource "google_kms_key_ring" "key_ring" {
  project  = var.google_project
  name     = "vault-cluster-f91e40fb"
  location = var.google_region
}

resource "google_kms_crypto_key" "crypto_key" {
  name            = "unseal"
  key_ring        = google_kms_key_ring.key_ring.self_link
  rotation_period = "100000s"
}

resource "google_kms_key_ring_iam_binding" "vault_iam_kms_binding" {
  key_ring_id = google_kms_key_ring.key_ring.id
  role        = "roles/owner"

  members = [
    "serviceAccount:${google_service_account.unseal.email}",
  ]
}

# GCP secrets provider
resource "vault_gcp_secret_backend" "gcp" {
  path                      = "gcp"
  description               = "Vault GCP Secrets backend"
  default_lease_ttl_seconds = 1200
  max_lease_ttl_seconds     = 86400
  credentials               = file("../ham-infrastructure-8830-7d13ed630217.json")
}

resource "vault_gcp_secret_roleset" "roleset" {
  backend      = vault_gcp_secret_backend.gcp.path
  roleset      = "project_viewer"
  secret_type  = "service_account_key"
  project      = var.google_project
  token_scopes = ["https://www.googleapis.com/auth/cloud-platform"]

  binding {
    resource = "//cloudresourcemanager.googleapis.com/projects/${var.google_project}"

    roles = [
      "roles/viewer",
    ]
  }
}

# Consul Connect CA
resource "vault_mount" "connect-root" {
  path                      = "connect_root"
  type                      = "pki"
  description               = "Consul Connect Root CA"
  default_lease_ttl_seconds = 3600
  max_lease_ttl_seconds     = 86400
}

resource "vault_mount" "connect-inter" {
  path                      = "connect_inter"
  type                      = "pki"
  description               = "Consul Connect Intermediate CA"
  default_lease_ttl_seconds = 3600
  max_lease_ttl_seconds     = 86400
}

resource "vault_policy" "consul-connect" {
  name   = "consult-connect"
  policy = <<EOT
      # Consul Managed PKI Mounts
      path "/sys/mounts" {
        capabilities = [ "read" ]
      }
      
      path "/sys/mounts/connect_root" {
        capabilities = [ "create", "read", "update", "delete", "list" ]
      }
      
      path "/sys/mounts/connect_inter" {
        capabilities = [ "create", "read", "update", "delete", "list" ]
      }
      
      path "/connect_root/*" {
        capabilities = [ "create", "read", "update", "delete", "list" ]
      }
      
      path "/connect_inter/*" {
        capabilities = [ "create", "read", "update", "delete", "list" ]
      }
  EOT
}
