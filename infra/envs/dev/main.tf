provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
  subscription_id = var.azure_subscription_id
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}

data "azurerm_container_registry" "shared" {
  name                = "cgregicesi"
  resource_group_name = "circleguard-shared-rg"
}

module "aks" {
  source          = "../../modules/aks"
  resource_group  = "circleguard-dev-rg"
  location        = var.location
  node_count      = 1
  acr_id          = data.azurerm_container_registry.shared.id
  cluster_name    = "circleguard-dev"
  dns_prefix      = "cg-dev"
  vm_size         = "Standard_D2s_v3"
  min_count       = 1
  max_count       = 3
  environment_tag = "dev"
}

module "k8s_addons" {
  source                = "../../modules/k8s-addons"
  enable_cert_manager   = true
  enable_monitoring     = false
  enable_sealed_secrets = true
  enable_keda           = false
  enable_elk            = false
  enable_istio          = false
  enable_chaos          = false
  enable_finops         = false

  depends_on = [module.aks]
}
