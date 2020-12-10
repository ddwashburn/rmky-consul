data "triton_image" "consul-server" {
  name    = "consul-server"
  version = "1.8.5-202010262350"
}

resource "triton_firewall_rule" "consul-ssh" {
  description = "Allow SSH to all Consul systems"
  rule        = "FROM any TO tag \"consul\" ALLOW tcp PORT 22"
  enabled     = true
}

# https://learn.hashicorp.com/tutorials/consul/reference-architecture?in=consul/datacenter-deploy#network-connectivity
# https://www.consul.io/docs/agent/options.html#ports
resource "triton_firewall_rule" "consul-server-tcp" {
  description = "Allow Consul server traffic"
  rule        = "FROM tag \"consul\" TO tag \"consul\" = \"server\" ALLOW tcp (PORT 8300 AND PORT 8301)"
  enabled     = true
}

resource "triton_firewall_rule" "consul-tcp" {
  description = "Allow Consul Gossip, HTTP/S, gRPC, and DNS traffic"
  rule        = "FROM tag \"consul\" TO tag \"consul\" ALLOW tcp (PORT 8301 AND PORT 8302 AND PORT 8500 AND PORT 8501 AND PORT 8502 AND PORT 8600)"
  enabled     = true
}

resource "triton_firewall_rule" "consul-udp" {
  description = "Allow Consul Gossip, gRPC and DNS traffic"
  rule        = "FROM tag \"consul\" TO tag \"consul\" ALLOW udp (PORT 8301 AND PORT 8302 AND PORT 8600)"
  enabled     = true
}

resource "triton_firewall_rule" "lan-consul-client" {
  description = "Allow Consul HTTP/S client traffic from LAN to Servers"
  rule        = "FROM subnet 172.23.1.0/26 TO tag \"consul\" ALLOW tcp (PORT 8300 AND PORT 8301 AND PORT 8302 AND PORT 8500 AND PORT 8501)"
  enabled     = true
}

data "consul_acl_policy" "global-management" {
  name = "global-management"
}

resource "consul_acl_policy" "server-policy" {
  datacenters = [data.triton_datacenter.current.name]
  description = "Node policy"
  name        = "node-policy"
  rules       = <<-RULE
    node "consul-0" {
      policy = "write"
    }
    node "consul-1" {
      policy = "write"
    }
    node "consul-2" {
      policy = "write"
    }
  RULE
}

resource "consul_acl_policy" "acl-admin" {
  datacenters = [data.triton_datacenter.current.name]
  description = "ACL Policy Administrator"
  name        = "acl-admin"
  rules       = <<-RULE
        "key_prefix" "" {
            policy = "read"
        }
        "key_prefix" "terraform/" {
            policy = "write"
        }
        "node_prefix" "" {
            policy = "write"
        }
        "agent_prefix" "" {
            policy = "write"
        }
        "session_prefix" "" {
            policy = "write"
        }

        acl = "write"

        operator = "read"
    RULE
}

resource "consul_acl_token" "terraform" {
  description = "Terraform Service Account"
  policies = [
    consul_acl_policy.acl-admin.name,
  ]
}

resource "triton_machine" "consul-server" {
  count   = 3
  name    = "consul-${count.index}"
  package = var.consul_package
  image   = data.triton_image.consul-server.id

  firewall_enabled = true

  affinity = [
    "instance!=~consul-0",
    "instance!=~consul-1",
    "instance!=~consul-2",
    "instance!=~consul-3",
  ]

  tags = {
    consul = "server"
  }

  cns {
    services = ["consul"]
  }

  metadata = {
    "user-script"        = local.user-script
    "rmky:consul-server" = "true"
    "consul-server"      = "true"
    "consul-join-addr"   = local.consul-join-addr
    "consul-gossip-key"  = local.consul-gossip-key
    "consul-agent-ca"    = local.consul-agent-ca
    "consul-agent-token" = var.consul-agent-token["consul-${count.index}"]
    "consul-server-cert" = file("../ca/${data.triton_datacenter.current.name}-server-consul-${count.index}.pem")
    "consul-server-key"  = file("../ca/${data.triton_datacenter.current.name}-server-consul-${count.index}-key.pem")
    "consul-metadata" = jsonencode({
      "consul-version" = split("-", data.triton_image.consul-server.version)[0]
      "package-name"   = var.consul_package,
      "image-name"     = data.triton_image.consul-server.name,
      "image-version"  = data.triton_image.consul-server.version,
    })
  }

  networks = [
    data.triton_network.external.id,
  ]
}
