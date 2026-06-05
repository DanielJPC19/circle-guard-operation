variable "enable_cert_manager" {
  type    = bool
  default = true
}

variable "enable_monitoring" {
  type    = bool
  default = true
}

variable "enable_elk" {
  type    = bool
  default = false
}

variable "enable_jaeger" {
  type    = bool
  default = false
}

variable "enable_istio" {
  type    = bool
  default = false
}

variable "enable_chaos" {
  type    = bool
  default = false
}

variable "enable_finops" {
  type    = bool
  default = false
}

variable "enable_keda" {
  type    = bool
  default = false
}

variable "enable_sealed_secrets" {
  type    = bool
  default = true
}
