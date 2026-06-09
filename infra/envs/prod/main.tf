provider "azurerm" {
  features {}
  subscription_id = var.azure_subscription_id
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}

# ACR is shared across environments — reference the existing registry
data "azurerm_container_registry" "shared" {
  name                = "cgregistry"
  resource_group_name = "circleguard-shared-rg"
}

module "aks" {
  source          = "../../modules/aks"
  resource_group  = "circleguard-prod-rg"
  location        = var.location
  node_count      = 3
  acr_id          = data.azurerm_container_registry.shared.id
  cluster_name    = "circleguard-prod"
  dns_prefix      = "cg-prod"
  vm_size         = "Standard_D2s_v3"
  min_count       = 2
  max_count       = 8
  environment_tag = "prod"
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
