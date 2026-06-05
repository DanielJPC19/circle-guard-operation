output "cluster_id" {
  value = azurerm_kubernetes_cluster.staging.id
}

output "kube_config" {
  value     = azurerm_kubernetes_cluster.staging.kube_config_raw
  sensitive = true
}

output "kubelet_identity" {
  value = azurerm_kubernetes_cluster.staging.kubelet_identity[0].object_id
}
