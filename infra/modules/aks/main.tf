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
  name                = "circleguard-logs-stage"
  location            = var.location
  resource_group_name = var.resource_group
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_kubernetes_cluster" "staging" {
  name                = "circleguard-stage"
  location            = var.location
  resource_group_name = var.resource_group
  dns_prefix          = "cg-stage"
  kubernetes_version  = "1.32"

  default_node_pool {
    name                = "system"
    node_count          = var.node_count
    vm_size             = "Standard_D2s_v3"
    enable_auto_scaling = true
    min_count           = 1
    max_count           = 4
    os_disk_size_gb     = 30

    node_labels = {
      environment = "staging"
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
    environment = "staging"
    managed-by  = "terraform"
  }
}

# Grant AKS managed identity pull access to ACR
resource "azurerm_role_assignment" "aks_acr" {
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.staging.kubelet_identity[0].object_id
}
