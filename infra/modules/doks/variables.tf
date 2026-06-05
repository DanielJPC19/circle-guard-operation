variable "region" {
  description = "DigitalOcean region"
  type        = string
  default     = "nyc1"
}

variable "node_count" {
  description = "Initial node count"
  type        = number
  default     = 2
}
