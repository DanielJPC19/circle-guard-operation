terraform {
  backend "azurerm" {
    resource_group_name  = "circleguard-tfstate-rg"
    storage_account_name = "cgtfstate"
    container_name       = "tfstate"
    key                  = "staging/terraform.tfstate"
  }
}
