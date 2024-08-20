# API Project with GKE Deployment

This project deploys a containerized API application to Google Kubernetes Engine (GKE) using Terraform for infrastructure management and GitHub Actions for CI/CD.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Project Structure](#project-structure)
3. [Setup](#setup)
4. [Deployment](#deployment)
5. [Verification](#verification)
6. [Troubleshooting](#troubleshooting)

## Prerequisites

- Google Cloud Platform (GCP) account
- Terraform installed locally
- `gcloud` CLI installed
- `kubectl` installed
- Docker installed (for local testing)

## Project Structure

```
.
├── .github
│   └── workflows
│       └── deploy.yml
├── terraform
│   ├── main.tf
│   └── variables.tf
├── app.py
└── requirements.txt
│  
├── Dockerfile
└── README.md
```

## Setup

1. Fork this repository.

2. Set up the following secrets in your GitHub repository:
   * `GCP_PROJECT_ID`: Your Google Cloud Project ID
   * `GCP_SA_KEY_B64`: Base64 encoded service account key
   * `GKE_CLUSTER`: Name of your GKE cluster
   * `GKE_REGION`: GCP region for your resources
   * `DOCKER_IMAGE_NAME`: Name of your Docker image (without registry or tag)
   * `TF_VAR_VPC_NAME`: Name for your VPC
   * `TF_VAR_SUBNET_NAME`: Name for your subnet
   * `TF_VAR_SUBNET_CIDR`: CIDR range for your subnet (e.g., "10.0.0.0/24")
   * `TF_VAR_NODE_POOL_NAME`: Name for your GKE node pool
   * `TF_VAR_NODE_COUNT`: Number of nodes in your GKE cluster
   * `TF_VAR_MACHINE_TYPE`: Machine type for GKE nodes (e.g., "e2-medium")
   * `TF_VAR_SERVICE_ACCOUNT_ID`: ID for the GKE service account
   * `TF_VAR_K8S_NAMESPACE`: Kubernetes namespace for your deployment
   * `TF_VAR_IAM_ROLES_TO_GRANT`: IAM roles to grant (comma-separated)
   * `TF_VAR_OPEN_PORTS`: Ports to open (comma-separated)
   * `TF_VAR_CONTAINER_IMAGE`: Full path to your container image (without registry or tag)
   * `TF_VAR_REPLICAS`: Number of replicas for your deployment

Note: To get the base64 encoded service account key, run:

```
base64 -w 0 path/to/your-service-account-key.json
```

3. Enable the following APIs in your GCP project:
   - Compute Engine API
   - Kubernetes Engine API
   - Container Registry API
   - Cloud Resource Manager API

4. Ensure your service account has the following roles:
   - Kubernetes Engine Developer
   - Storage Admin
   - Service Account User
   - Compute Storage Admin
   - Compute Network Admin
   - Artifact Registry Writer

## Deployment

The deployment process is automated using GitHub Actions. When you push to the `main` branch, it triggers the workflow defined in `.github/workflows/deploy.yml`.

The workflow does the following:
1. Sets up the GCP environment
2. Builds and pushes the Docker image to Artifact Registry
3. Applies Terraform configurations to set up GKE and other resources
4. Deploys the application to GKE

## Verification

After deployment, the workflow verifies the API's accessibility. It retrieves the Load Balancer IP and checks if the API responds with a 200 status code.

To manually verify:
1. Get the Load Balancer IP:
   ```
   kubectl get service assignment-service -n assignment -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
   ```
2. Access the API:
   ```
   curl http://<LOAD_BALANCER_IP>
   ```

## Troubleshooting

- If the API is not accessible, check the service and pod status:
  ```
  kubectl get services,pods -n assignment
  ```
- Review the GitHub Actions logs for any error messages.
- Ensure all required GCP APIs are enabled.
- Verify that the service account has the necessary permissions.

For more detailed logs:
```
kubectl logs -n assignment <pod-name>
```

## Notes

- The initial deployment may take up to 15 minutes for the Load Balancer to be fully provisioned.
- Ensure your GCP billing is set up correctly to avoid deployment issues.

For any additional questions or issues, please open an issue in this repository.
