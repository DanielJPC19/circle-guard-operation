output "cluster_id" {
  value = digitalocean_kubernetes_cluster.dev.id
}

output "cluster_endpoint" {
  value = digitalocean_kubernetes_cluster.dev.endpoint
}

output "kubeconfig" {
  value     = digitalocean_kubernetes_cluster.dev.kube_config[0].raw_config
  sensitive = true
}
