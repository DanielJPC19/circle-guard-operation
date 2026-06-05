output "cluster_name" {
  value = google_container_cluster.prod.name
}

output "cluster_endpoint" {
  value     = google_container_cluster.prod.endpoint
  sensitive = true
}

output "ca_certificate" {
  value     = google_container_cluster.prod.master_auth[0].cluster_ca_certificate
  sensitive = true
}

output "gke_sa_email" {
  value = google_service_account.gke_sa.email
}
