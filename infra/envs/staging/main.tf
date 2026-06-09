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
  source         = "../../modules/aks"
  resource_group = "circleguard-stage-rg"
  location       = var.location
  node_count     = 2
  acr_id         = data.azurerm_container_registry.shared.id
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

  depends_on = [module.aks]
}
