output "cluster_name" {
  value = module.eks.cluster_name
}

output "argocd_server_hostname" {
  description = "Public DNS once the LoadBalancer is ready"
  value       = try(data.kubernetes_service.argocd_server.status[0].load_balancer[0].ingress[0].hostname, null)
}

