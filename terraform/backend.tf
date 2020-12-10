terraform {
  backend "consul" {
    scheme = "http"
    path   = "terraform/consul"

    #    datacenter = "cle-1"
    ca_file   = "../ca/consul-agent-ca.pem"
    cert_file = "../ca/cle-1-client-consul-1.pem"
    key_file  = "../ca/cle-1-client-consul-1-key.pem"
  }
}

/*
*/

