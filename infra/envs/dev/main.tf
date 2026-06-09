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
  resource_group  = "circleguard-dev-rg"
  location        = var.location
  node_count      = 2
  acr_id          = data.azurerm_container_registry.shared.id
  cluster_name    = "circleguard-dev"
  dns_prefix      = "cg-dev"
  vm_size         = "Standard_B2s_v2"
  min_count       = 1
  max_count       = 3
  environment_tag = "dev"
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

  depends_on = [module.aks]
}
