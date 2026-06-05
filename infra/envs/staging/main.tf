provider "azurerm" {
  features {}
  subscription_id = var.azure_subscription_id
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}

module "acr" {
  source         = "../../modules/acr"
  acr_name       = "cgregistry"
  resource_group = "circleguard-shared-rg"
  location       = var.location
}

module "aks" {
  source         = "../../modules/aks"
  resource_group = "circleguard-stage-rg"
  location       = var.location
  node_count     = 2
  acr_id         = module.acr.acr_id
}

module "k8s_addons" {
  source                = "../../modules/k8s-addons"
  enable_cert_manager   = true
  enable_monitoring     = true
  enable_sealed_secrets = true
  enable_elk            = true
  enable_jaeger         = true
  enable_istio          = true
  enable_chaos          = true
  enable_finops         = true
  enable_keda           = false
}
