variable "resource_group" {
  description = "Azure resource group name"
  type        = string
  default     = "circleguard-stage-rg"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus"
}

variable "node_count" {
  description = "Initial node count"
  type        = number
  default     = 2
}

variable "acr_id" {
  description = "ACR resource ID for pull role assignment"
  type        = string
}
