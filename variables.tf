variable "project_id" {
  description = "The GCP Project ID"
  type        = string
}

variable "region" {
  description = "The GCP region to deploy resources"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "The GCP zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

variable "cluster_name" {
  description = "Name of the GKE cluster"
  type        = string
  default     = "assignment-gke-cluster"
}

variable "node_pool_name" {
  description = "Name of the GKE node pool"
  type        = string
  default     = "assignment-node-pool"
}

variable "vpc_name" {
  description = "Name of the VPC network"
  type        = string
  default     = "assignment-vpc"
}

variable "subnet_name" {
  description = "Name of the subnet"
  type        = string
  default     = "assignment-subnet"
}

variable "subnet_cidr" {
  description = "CIDR range for the subnet"
  type        = string
  default     = "10.0.0.0/24"
}

variable "service_account_id" {
  description = "ID for the GKE service account"
  type        = string
  default     = "gke-service-account"
}