terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }
}

resource "digitalocean_kubernetes_cluster" "dev" {
  name    = "circleguard-dev"
  region  = var.region
  version = "1.32.x-do.0"

  node_pool {
    name       = "worker"
    size       = "s-2vcpu-4gb"
    node_count = var.node_count
    auto_scale = true
    min_nodes  = 1
    max_nodes  = 3

    labels = {
      environment = "dev"
      managed-by  = "terraform"
    }
  }

  tags = ["circleguard", "dev"]
}
