variable "project_id" {
  description = "The GCP Project ID"
}

variable "region" {
  description = "The GCP region to deploy resources"
}

variable "vpc_name" {
  description = "Name of the VPC"
}

variable "subnet_name" {
  description = "Name of the subnet"
}

variable "subnet_cidr" {
  description = "CIDR range for the subnet"
}

variable "cluster_name" {
  description = "Name of the GKE cluster"
}

variable "node_pool_name" {
  description = "Name of the GKE node pool"
}

variable "node_count" {
  description = "Number of nodes in the GKE node pool"
  type        = number
}

variable "machine_type" {
  description = "Machine type for GKE nodes"
}

variable "service_account_id" {
  description = "ID for the GKE service account"
}

variable "k8s_namespace" {
  description = "Kubernetes namespace for the assignment"
}

variable "iam_roles_to_grant" {
  description = "List of IAM roles to grant to the GKE service account"
  type        = list(string)
}

variable "open_ports" {
  description = "List of ports to open in the firewall"
  type        = list(string)
}

variable "container_image" {
  description = "Name of the container image"
}

variable "container_version" {
  description = "Version of the container image"
}

variable "replicas" {
  description = "Number of replicas for the Kubernetes deployment"
  type        = number
}

variable "allowed_ips" {
  description = "CIDR range allowed to access the GKE cluster"
  type        = string
  default     = "102.90.0.0/16"  # This covers a range of IPs; adjust as needed
}