provider "azurerm" {
  features {}
  subscription_id = var.azure_subscription_id
}

resource "azurerm_resource_group" "shared" {
  name     = "circleguard-shared-rg"
  location = var.location
}

module "acr" {
  source         = "../../modules/acr"
  acr_name       = "cgregicesi"
  resource_group = azurerm_resource_group.shared.name
  location       = var.location
  depends_on     = [azurerm_resource_group.shared]
}
