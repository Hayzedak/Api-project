provider "google" {
  project = var.project_id
  region  = var.region
}

data "google_client_config" "default" {}

#terraform {
#  backend "gcs" {
 #   bucket  = "assignment-bucket-tfstate"
  #  prefix  = "terraform/state"
#  }
#}

provider "kubernetes" {
  host  = "https://${google_container_cluster.primary.endpoint}"
  token = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(
    google_container_cluster.primary.master_auth[0].cluster_ca_certificate,
  )
}

# Policy as Code
locals {
  allowed_iam_roles = [
    "roles/container.developer",
    "roles/storage.objectViewer"
  ]
  allowed_open_ports = ["80", "443", "3000"]
}

resource "terraform_data" "iam_policy_check" {
  count = length(var.iam_roles_to_grant)

  lifecycle {
    precondition {
      condition     = contains(local.allowed_iam_roles, var.iam_roles_to_grant[count.index])
      error_message = "IAM role ${var.iam_roles_to_grant[count.index]} is not allowed. Allowed roles are: ${join(", ", local.allowed_iam_roles)}"
    }
  }
}

resource "terraform_data" "firewall_policy_check" {
  lifecycle {
    precondition {
      condition     = alltrue([for port in var.open_ports : contains(local.allowed_open_ports, port)])
      error_message = "One or more specified ports are not allowed to be opened. Allowed ports are: ${join(", ", local.allowed_open_ports)}"
    }
  }
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
  private_ip_google_access = true
}

# NAT Gateway
resource "google_compute_router" "router" {
  name    = "my-router"
  region  = var.region
  network = google_compute_network.vpc.self_link
}

resource "google_compute_router_nat" "nat" {
  name                               = "my-router-nat"
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

resource "google_compute_firewall" "allow_kubectl_access" {
  name    = "allow-kubectl-access"
  network = google_compute_network.vpc.name
  
  allow {
    protocol = "tcp"
    ports    = ["443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["gke-node"]
}

resource "google_compute_firewall" "allow_github_actions" {
  name    = "allow-github-actions"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["443", "8443", "10250"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["gke-node"]
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
    enable_private_nodes    = false
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  ip_allocation_policy {
    cluster_ipv4_cidr_block  = "/16"
    services_ipv4_cidr_block = "/22"
  }

#  master_authorized_networks_config {
#    cidr_blocks {
#      cidr_block   = var.allowed_ips
#      display_name = "Allowed IP Range"
#    }
#  }

  network_policy {
    enabled = true
  }

  addons_config {
    network_policy_config {
      disabled = false
    }
  }

  deletion_protection = false 
}

resource "google_container_node_pool" "primary_nodes" {
  name       = var.node_pool_name
  location   = var.region
  cluster    = google_container_cluster.primary.name
  
  initial_node_count = var.node_count

  autoscaling {
    min_node_count = var.node_count
    max_node_count = 3
  }

  node_config {
    preemptible  = true
    machine_type = var.machine_type

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    tags = ["gke-node"]
  }
}

# Create a delay
resource "time_sleep" "wait_for_kubernetes" {
  depends_on = [google_container_cluster.primary, google_container_node_pool.primary_nodes]
  create_duration = "300s"
}

# Ensure cluster is accessible
resource "null_resource" "kubectl_setup" {
  depends_on = [google_container_cluster.primary, google_container_node_pool.primary_nodes, time_sleep.wait_for_kubernetes]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command = join("\n", [
      "echo 'Setting up kubectl...'",
      "gcloud components install gke-gcloud-auth-plugin -q",
      "gcloud config set project '${var.project_id}'",
      "gcloud container clusters get-credentials '${google_container_cluster.primary.name}' --region '${var.region}' --project '${var.project_id}'",
      "echo 'Waiting for nodes to be ready...'",
      "for i in $(seq 1 10); do",
      "  if kubectl wait --for=condition=Ready nodes --all --timeout=60s; then",
      "    echo 'Nodes are ready'",
      "    break",
      "  fi",
      "  echo \"Waiting for nodes... Attempt $i\"",
      "  sleep 30",
      "done",
      "echo 'Fetching nodes...'",
      "kubectl get nodes"
    ])
  }

  triggers = {
    cluster_ep = google_container_cluster.primary.endpoint
  }
}

# IAM Roles and Policies
resource "google_service_account" "gke_sa" {
  account_id   = var.service_account_id
  display_name = "GKE Service Account"
}

resource "google_project_iam_member" "gke_sa_roles" {
  count   = length(var.iam_roles_to_grant)
  project = var.project_id
  role    = var.iam_roles_to_grant[count.index]
  member  = "serviceAccount:${google_service_account.gke_sa.email}"

  depends_on = [terraform_data.iam_policy_check]
}

# Kubernetes Namespace
resource "kubernetes_namespace" "assignment" {
  depends_on = [null_resource.kubectl_setup]
  metadata {
    name = var.k8s_namespace
  }

  lifecycle {
    ignore_changes = [
      metadata[0].labels,
      metadata[0].annotations,
    ]
  }
}

# Kubernetes ConfigMap
resource "kubernetes_config_map" "api_config" {
  depends_on = [null_resource.kubectl_setup, kubernetes_namespace.assignment]
  metadata {
    name      = "api-config"
    namespace = var.k8s_namespace
  }

}

# Kubernetes Deployment
resource "kubernetes_deployment" "assignment" {
  depends_on = [null_resource.kubectl_setup, kubernetes_config_map.api_config]
  metadata {
    name      = "assignment-deployment"
    namespace = var.k8s_namespace
  }

  spec {
    replicas = var.replicas

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
          image = "${var.region}-docker.pkg.dev/${var.project_id}/docker-repo/${var.container_image}:${var.container_version}"
          name  = "assignment"

          port {
            container_port = 3000
          }

          env_from {
            config_map_ref {
              name = kubernetes_config_map.api_config.metadata[0].name
            }
          }

          env {
            name  = "PORT"
            value = "3000"
          }
        }
      }
    }
  }
}

# Kubernetes Service
resource "kubernetes_service" "assignment" {
  depends_on = [null_resource.kubectl_setup, kubernetes_deployment.assignment]
  metadata {
    name      = "assignment-service"
    namespace = var.k8s_namespace
  }

  spec {
    selector = {
      app = "assignment"
    }

    port {
      port        = 80
      target_port = 3000
    }

    type = "LoadBalancer"
  }
}

# Kubernetes Ingress
resource "kubernetes_ingress_v1" "assignment" {
  depends_on = [null_resource.kubectl_setup, kubernetes_service.assignment]
  metadata {
    name      = "assignment-ingress"
    namespace = var.k8s_namespace
    annotations = {
      "kubernetes.io/ingress.class"                 = "gce"
      "kubernetes.io/ingress.global-static-ip-name" = google_compute_global_address.ingress_ip.name
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

resource "google_compute_global_address" "ingress_ip" {
  name = "assignment-ingress-ip"
}

output "load_balancer_ip" {
  value = google_compute_global_address.ingress_ip.address
}
