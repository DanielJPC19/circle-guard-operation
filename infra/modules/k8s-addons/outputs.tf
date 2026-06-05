output "sealed_secrets_status" {
  description = "Sealed Secrets helm release status"
  value       = length(helm_release.sealed_secrets) > 0 ? helm_release.sealed_secrets[0].status : "disabled"
}

output "cert_manager_status" {
  description = "cert-manager helm release status"
  value       = length(helm_release.cert_manager) > 0 ? helm_release.cert_manager[0].status : "disabled"
}

output "prometheus_stack_status" {
  description = "kube-prometheus-stack helm release status"
  value       = length(helm_release.prometheus_stack) > 0 ? helm_release.prometheus_stack[0].status : "disabled"
}

output "elasticsearch_status" {
  description = "Elasticsearch helm release status"
  value       = length(helm_release.elasticsearch) > 0 ? helm_release.elasticsearch[0].status : "disabled"
}

output "jaeger_status" {
  description = "Jaeger helm release status"
  value       = length(helm_release.jaeger) > 0 ? helm_release.jaeger[0].status : "disabled"
}

output "istio_status" {
  description = "Istio (istiod) helm release status"
  value       = length(helm_release.istiod) > 0 ? helm_release.istiod[0].status : "disabled"
}

output "kiali_status" {
  description = "Kiali helm release status"
  value       = length(helm_release.kiali) > 0 ? helm_release.kiali[0].status : "disabled"
}

output "chaos_mesh_status" {
  description = "Chaos Mesh helm release status"
  value       = length(helm_release.chaos_mesh) > 0 ? helm_release.chaos_mesh[0].status : "disabled"
}

output "kubecost_status" {
  description = "Kubecost helm release status"
  value       = length(helm_release.kubecost) > 0 ? helm_release.kubecost[0].status : "disabled"
}

output "keda_status" {
  description = "KEDA helm release status"
  value       = length(helm_release.keda) > 0 ? helm_release.keda[0].status : "disabled"
}

output "addons_summary" {
  description = "Summary of all installed addons and their namespaces"
  value = {
    sealed_secrets    = length(helm_release.sealed_secrets) > 0 ? "kube-system" : null
    cert_manager      = length(helm_release.cert_manager) > 0 ? "cert-manager" : null
    prometheus        = length(helm_release.prometheus_stack) > 0 ? "monitoring" : null
    elasticsearch     = length(helm_release.elasticsearch) > 0 ? "logging" : null
    kibana            = length(helm_release.kibana) > 0 ? "logging" : null
    jaeger            = length(helm_release.jaeger) > 0 ? "tracing" : null
    istio             = length(helm_release.istiod) > 0 ? "istio-system" : null
    kiali             = length(helm_release.kiali) > 0 ? "istio-system" : null
    chaos_mesh        = length(helm_release.chaos_mesh) > 0 ? "chaos-testing" : null
    kubecost          = length(helm_release.kubecost) > 0 ? "kubecost" : null
    keda              = length(helm_release.keda) > 0 ? "keda" : null
  }
}
