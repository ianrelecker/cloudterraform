########################################
# VPC
########################################
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = var.name
  cidr = var.vpc_cidr

  azs               = ["${var.region}a", "${var.region}b", "${var.region}c"]
  private_subnets   = ["10.0.0.0/19", "10.0.32.0/19", "10.0.64.0/19"]
  public_subnets    = ["10.0.96.0/20", "10.0.112.0/20", "10.0.128.0/20"]
  enable_nat_gateway = true
  single_nat_gateway = true

  public_subnet_tags  = { "kubernetes.io/role/elb" = "1" }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = "1" }
}

########################################
# EKS (IRSA enabled)
########################################
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  cluster_name    = var.name
  cluster_version = "1.29"
  subnet_ids      = module.vpc.private_subnets
  vpc_id          = module.vpc.vpc_id

  enable_irsa = true

  eks_managed_node_groups = {
    default = {
      instance_types = ["t3.large"]
      min_size       = 1
      max_size       = 3
      desired_size   = 2
    }
  }
}

########################################
# Argo CD via Helm
########################################
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = kubernetes_namespace.argocd.metadata[0].name
  version    = "5.46.8"

  values = [yamlencode({
    server = { service = { type = "LoadBalancer" } }
  })]

  depends_on = [module.eks]
}

# For outputs: read argocd-server Service (after helm install)
data "kubernetes_service" "argocd_server" {
  metadata {
    name      = "argocd-server"
    namespace = kubernetes_namespace.argocd.metadata[0].name
  }

  depends_on = [helm_release.argocd]
}

########################################
# GitOps demo app (Argo CD Application CRD)
########################################
resource "kubernetes_manifest" "podinfo_app" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "podinfo"
      namespace = kubernetes_namespace.argocd.metadata[0].name
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://stefanprodan.github.io/podinfo"
        chart          = "podinfo"
        targetRevision = "6.9.1"
        helm = {
          values = <<-EOT
            replicaCount: 2
            service:
              type: LoadBalancer
          EOT
        }
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "default"
      }
      syncPolicy = {
        automated = { prune = true, selfHeal = true }
      }
    }
  }

  depends_on = [helm_release.argocd]
}

