# Terraform EKS + Argo CD + GitOps Demo

Terraform-only AWS deploy that stands up:
- A VPC
- An EKS cluster (with IRSA enabled)
- Argo CD via `helm_release`
- A GitOps-managed demo app (podinfo) via an Argo CD Application (`kubernetes_manifest`)

## Files
- `providers.tf` – providers and EKS auth wiring
- `variables.tf` – region, name, vpc_cidr
- `main.tf` – VPC, EKS, Argo CD Helm release, Argo CD Application
- `outputs.tf` – cluster name and Argo CD server hostname

## How to run
```
cd infra
terraform init
terraform apply -auto-approve
```

Wait a few minutes for EKS nodes and the Argo CD LoadBalancer to become ready.

### Get Argo CD initial admin password
```
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

### Access Argo CD
- Port-forward: `kubectl -n argocd port-forward svc/argocd-server 8080:443` and open `https://localhost:8080` (user: `admin`, password: above)
- Or use the LoadBalancer DNS from output `argocd_server_hostname` once available

## Notes
- In production, consider installing an Ingress Controller (e.g., AWS Load Balancer Controller) and DNS instead of a public LoadBalancer.
- `kubernetes_manifest` lets Terraform apply Argo CD’s `Application` CRD after Argo CD is installed. The explicit dependency ensures correct ordering.

