terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

resource "azurerm_resource_group" "staging" {
  name     = var.resource_group
  location = var.location
}

resource "azurerm_log_analytics_workspace" "staging" {
  depends_on          = [azurerm_resource_group.staging]
  name                = "circleguard-logs-${var.environment_tag}"
  location            = var.location
  resource_group_name = var.resource_group
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_kubernetes_cluster" "staging" {
  name                = var.cluster_name
  location            = var.location
  resource_group_name = var.resource_group
  dns_prefix          = var.dns_prefix
  kubernetes_version  = "1.34.8"
  oidc_issuer_enabled = true

  default_node_pool {
    name                = "system"
    node_count          = var.node_count
    vm_size             = var.vm_size
    enable_auto_scaling = true
    min_count           = var.min_count
    max_count           = var.max_count
    os_disk_size_gb     = 30
    max_pods            = 50

    node_labels = {
      environment = var.environment_tag
    }
  }

  identity {
    type = "SystemAssigned"
  }

  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.staging.id
  }

  network_profile {
    network_plugin = "azure"
    network_policy = "calico"
  }

  tags = {
    environment = var.environment_tag
    managed-by  = "terraform"
  }
}

# Grant AKS managed identity pull access to ACR
resource "azurerm_role_assignment" "aks_acr" {
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.staging.kubelet_identity[0].object_id
}
