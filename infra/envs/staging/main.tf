provider "azurerm" {
  features {}
  subscription_id = var.azure_subscription_id
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}

# Shared resource group — created once, used by ACR and referenced by dev/prod
resource "azurerm_resource_group" "shared" {
  name     = "circleguard-shared-rg"
  location = var.location
}

# ACR — created in staging, referenced as data source by dev and prod
module "acr" {
  source         = "../../modules/acr"
  acr_name       = "cgregicesi"
  resource_group = azurerm_resource_group.shared.name
  location       = var.location

  depends_on = [azurerm_resource_group.shared]
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

  depends_on = [module.aks]
}
