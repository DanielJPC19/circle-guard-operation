terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

resource "google_container_cluster" "prod" {
  name                     = "circleguard-prod"
  location                 = var.region
  project                  = var.project_id
  remove_default_node_pool = true
  initial_node_count       = 1
  deletion_protection      = true

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  network    = "default"
  subnetwork = "default"
}

resource "google_container_node_pool" "prod_nodes" {
  name       = "prod-pool"
  cluster    = google_container_cluster.prod.name
  location   = var.region
  project    = var.project_id
  node_count = var.node_count

  autoscaling {
    min_node_count = 2
    max_node_count = 8
  }

  node_config {
    machine_type = "e2-standard-4"
    disk_size_gb = 50
    image_type   = "COS_CONTAINERD"

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    labels = {
      environment = "production"
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}

# Service account for GKE to pull from ACR (via image pull secret)
resource "google_service_account" "gke_sa" {
  account_id   = "circleguard-gke-sa"
  display_name = "CircleGuard GKE Service Account"
  project      = var.project_id
}
