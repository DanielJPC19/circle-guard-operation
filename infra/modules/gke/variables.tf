variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "node_count" {
  description = "Initial node count per zone"
  type        = number
  default     = 3
}
