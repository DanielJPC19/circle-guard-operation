provider "digitalocean" {
  token = var.do_token
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}

module "doks" {
  source     = "../../modules/doks"
  region     = var.region
  node_count = 2
}

module "k8s_addons" {
  source                = "../../modules/k8s-addons"
  enable_cert_manager   = true
  enable_monitoring     = true
  enable_sealed_secrets = true
  enable_keda           = true
  enable_elk            = false
  enable_istio          = false
  enable_chaos          = false
  enable_finops         = true
}
