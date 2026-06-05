terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
  }
}

resource "helm_release" "sealed_secrets" {
  count            = var.enable_sealed_secrets ? 1 : 0
  name             = "sealed-secrets"
  repository       = "https://bitnami-labs.github.io/sealed-secrets"
  chart            = "sealed-secrets"
  version          = "~> 2.15"
  namespace        = "kube-system"
}

resource "helm_release" "cert_manager" {
  count            = var.enable_cert_manager ? 1 : 0
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = "~> 1.15"
  namespace        = "cert-manager"
  create_namespace = true

  set {
    name  = "installCRDs"
    value = "true"
  }
}

resource "helm_release" "prometheus_stack" {
  count            = var.enable_monitoring ? 1 : 0
  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = "~> 61.0"
  namespace        = "monitoring"
  create_namespace = true

  set {
    name  = "grafana.adminPassword"
    value = "circleguard-grafana"
  }
}

resource "helm_release" "elasticsearch" {
  count            = var.enable_elk ? 1 : 0
  name             = "elasticsearch"
  repository       = "https://helm.elastic.co"
  chart            = "elasticsearch"
  version          = "~> 8.5"
  namespace        = "logging"
  create_namespace = true
}

resource "helm_release" "kibana" {
  depends_on       = [helm_release.elasticsearch]
  count            = var.enable_elk ? 1 : 0
  name             = "kibana"
  repository       = "https://helm.elastic.co"
  chart            = "kibana"
  version          = "~> 8.5"
  namespace        = "logging"
  create_namespace = true
}

resource "helm_release" "jaeger" {
  count            = var.enable_jaeger ? 1 : 0
  name             = "jaeger"
  repository       = "https://jaegertracing.github.io/helm-charts"
  chart            = "jaeger"
  version          = "~> 3.0"
  namespace        = "tracing"
  create_namespace = true
}

resource "helm_release" "istio_base" {
  count            = var.enable_istio ? 1 : 0
  name             = "istio-base"
  repository       = "https://istio-release.storage.googleapis.com/charts"
  chart            = "base"
  version          = "~> 1.22"
  namespace        = "istio-system"
  create_namespace = true
}

resource "helm_release" "istiod" {
  depends_on       = [helm_release.istio_base]
  count            = var.enable_istio ? 1 : 0
  name             = "istiod"
  repository       = "https://istio-release.storage.googleapis.com/charts"
  chart            = "istiod"
  version          = "~> 1.22"
  namespace        = "istio-system"
}

resource "helm_release" "istio_ingress" {
  depends_on       = [helm_release.istiod]
  count            = var.enable_istio ? 1 : 0
  name             = "istio-ingressgateway"
  repository       = "https://istio-release.storage.googleapis.com/charts"
  chart            = "gateway"
  version          = "~> 1.22"
  namespace        = "istio-system"
}

resource "helm_release" "kiali" {
  depends_on       = [helm_release.istiod]
  count            = var.enable_istio ? 1 : 0
  name             = "kiali-server"
  repository       = "https://kiali.org/helm-charts"
  chart            = "kiali-server"
  version          = "~> 1.87"
  namespace        = "istio-system"
}

resource "helm_release" "chaos_mesh" {
  count            = var.enable_chaos ? 1 : 0
  name             = "chaos-mesh"
  repository       = "https://charts.chaos-mesh.org"
  chart            = "chaos-mesh"
  version          = "~> 2.7"
  namespace        = "chaos-testing"
  create_namespace = true
}

resource "helm_release" "kubecost" {
  count            = var.enable_finops ? 1 : 0
  name             = "kubecost"
  repository       = "https://kubecost.github.io/cost-analyzer"
  chart            = "cost-analyzer"
  version          = "~> 2.3"
  namespace        = "kubecost"
  create_namespace = true

  set {
    name  = "prometheus.enabled"
    value = "false"
  }

  set {
    name  = "global.prometheus.fqdn"
    value = "http://kube-prometheus-stack-prometheus.monitoring:9090"
  }
}

resource "helm_release" "keda" {
  count            = var.enable_keda ? 1 : 0
  name             = "keda"
  repository       = "https://kedacore.github.io/charts"
  chart            = "keda"
  version          = "~> 2.14"
  namespace        = "keda"
  create_namespace = true
}
