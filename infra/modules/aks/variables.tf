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

variable "cluster_name" {
  description = "AKS cluster name"
  type        = string
  default     = "circleguard-stage"
}

variable "dns_prefix" {
  description = "AKS DNS prefix"
  type        = string
  default     = "cg-stage"
}

variable "vm_size" {
  description = "Node VM size"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "min_count" {
  description = "Minimum node count for autoscaler"
  type        = number
  default     = 1
}

variable "max_count" {
  description = "Maximum node count for autoscaler"
  type        = number
  default     = 4
}

variable "environment_tag" {
  description = "Value for the 'environment' tag and node label"
  type        = string
  default     = "staging"
}
