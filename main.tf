provider "google" {
  project = var.project_id
  region  = var.region
}

data "google_client_config" "default" {}


provider "kubernetes" {
  host                   = "https://${google_container_cluster.primary.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
}

# VPC and Networking
resource "google_compute_network" "vpc" {
  name                    = var.vpc_name
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  name          = var.subnet_name
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.vpc.self_link
}

# NAT Gateway
resource "google_compute_router" "router" {
  name    = "assignment-router"
  region  = google_compute_subnetwork.subnet.region
  network = google_compute_network.vpc.self_link
}

resource "google_compute_router_nat" "nat" {
  name                               = "assignment-router-nat"
  router                             = google_compute_router.router.name
  region                             = google_compute_router.router.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

# Firewall Rules
resource "google_compute_firewall" "allow_internal" {
  name    = "allow-internal"
  network = google_compute_network.vpc.name

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  source_ranges = [var.subnet_cidr]
}

#resource "google_compute_firewall" "deny_external_ip_access" {
#  name    = "deny-external-ip-access"
#  network = google_compute_network.vpc.name
#
#  deny {
#    protocol = "all"
#  }
#
#  source_ranges = ["0.0.0.0/0"]
#
#  target_tags = ["no-external-ip"]
#}

resource "google_compute_firewall" "allow_wsl_and_localhost" {
  name    = "allow-wsl-and-localhost"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["443"] 
  }

  source_ranges = ["172.30.226.117/32", "127.0.0.1/32"]
  target_tags   = ["no-external-ip"]
}

# GKE Cluster
resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = var.region

  remove_default_node_pool = true
  initial_node_count       = 1

  network    = google_compute_network.vpc.self_link
  subnetwork = google_compute_subnetwork.subnet.self_link

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  ip_allocation_policy {
    cluster_ipv4_cidr_block  = "/16"
    services_ipv4_cidr_block = "/22"
  }

  deletion_protection = false 
}

resource "google_container_node_pool" "primary_nodes" {
  name       = var.node_pool_name
  location   = var.region
  cluster    = google_container_cluster.primary.name
  node_count = 1

  node_config {
    preemptible  = true
    machine_type = "e2-micro"

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    tags = ["no-external-ip"]
  }
}

# Create a delay
resource "time_sleep" "wait_for_kubernetes" {
  depends_on = [google_container_node_pool.primary_nodes]
  create_duration = "30s"
}

# IAM Roles and Policies
resource "google_project_iam_member" "gke_sa_role" {
  project = var.project_id
  role    = "roles/container.developer"
  member  = "serviceAccount:${google_service_account.gke_sa.email}"
}

resource "google_service_account" "gke_sa" {
  account_id   = var.service_account_id
  display_name = "GKE Service Account"
}

# Kubernetes Namespace
resource "kubernetes_namespace" "assignment" {
  depends_on = [time_sleep.wait_for_kubernetes]
  metadata {
    name = "assignment"
  }
}

# Kubernetes Deployment
resource "google_compute_firewall" "allow_kubernetes_api" {
  name    = "allow-kubernetes-api"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }

  source_ranges = ["0.0.0.0/0"]  # Change to your IP range for security
}


resource "kubernetes_deployment" "assignment" {
  metadata {
    name      = "assignment-deployment"
    namespace = kubernetes_namespace.assignment.metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "assignment"
      }
    }

    template {
      metadata {
        labels = {
          app = "assignment"
        }
      }

      spec {
        container {
          image = "gcr.io/${var.project_id}/assignment-api:latest"
          name  = "assignment"

          port {
            container_port = 3000
          }
        }
      }
    }
  }
}

# Kubernetes Service
resource "kubernetes_service" "assignment" {
  metadata {
    name      = "assignment-service"
    namespace = kubernetes_namespace.assignment.metadata[0].name
  }

  spec {
    selector = {
      app = kubernetes_deployment.assignment.spec[0].template[0].metadata[0].labels.app
    }

    port {
      port        = 80
      target_port = 3000
    }

    type = "LoadBalancer"
  }
}

# Kubernetes Ingress
# Kubernetes Ingress
resource "kubernetes_ingress_v1" "assignment" {
  metadata {
    name      = "assignment-ingress"
    namespace = kubernetes_namespace.assignment.metadata[0].name
    annotations = {
      "kubernetes.io/ingress.class" = "gce"  
    }
  }

  spec {
    rule {
      http {
        path {
          path = "/"  
          path_type = "Prefix"  
          backend {
            service {
              name = kubernetes_service.assignment.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
}
