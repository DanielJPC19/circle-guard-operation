provider "google" {
  project = var.gcp_project
  region  = var.region
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}

module "gke" {
  source     = "../../modules/gke"
  project_id = var.gcp_project
  region     = var.region
  node_count = 3
}

module "k8s_addons" {
  source                = "../../modules/k8s-addons"
  enable_cert_manager   = true
  enable_monitoring     = true
  enable_sealed_secrets = true
  enable_elk            = true
  enable_jaeger         = true
  enable_istio          = true
  enable_chaos          = false
  enable_finops         = true
  enable_keda           = false
}
