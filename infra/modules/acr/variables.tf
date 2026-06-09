variable "acr_name" {
  description = "Azure Container Registry name (globally unique)"
  type        = string
  default     = "cgregicesi"
}

variable "resource_group" {
  description = "Azure resource group name"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "brazilsouth"
}
