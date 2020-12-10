data "triton_datacenter" "current" {}

data "triton_account" "current" {}

data "triton_network" "external" {
  name = var.external_network
}

locals {
  consul-join-addr  = "consul.svc.${data.triton_account.current.id}.${data.triton_datacenter.current.name}.cns.rmky.org"
  consul-agent-ca   = file("../ca/consul-agent-ca.pem")
  consul-gossip-key = file("../ca/gossip.key")
  user-script       = file("../packer/rmky.files/user-script.sh")
}
