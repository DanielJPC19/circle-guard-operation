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
  version          = "2.15.4"
  namespace        = "kube-system"
}

resource "helm_release" "cert_manager" {
  depends_on       = [helm_release.sealed_secrets]
  count            = var.enable_cert_manager ? 1 : 0
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = "1.15.5"
  namespace        = "cert-manager"
  create_namespace = true

  set {
    name  = "installCRDs"
    value = "true"
  }
}

resource "helm_release" "prometheus" {
  depends_on       = [helm_release.cert_manager]
  count            = var.enable_monitoring ? 1 : 0
  name             = "prometheus"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "prometheus"
  version          = "25.0.0"
  namespace        = "monitoring"
  create_namespace = true
  timeout          = 600
  wait             = false

  set {
    name  = "server.retention"
    value = "7d"
  }

  set {
    name  = "server.persistentVolume.enabled"
    value = "false"
  }

  set {
    name  = "alertmanager.enabled"
    value = "false"
  }

  set {
    name  = "pushgateway.enabled"
    value = "false"
  }

  set {
    name  = "server.resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "server.resources.requests.memory"
    value = "256Mi"
  }

  set {
    name  = "server.resources.limits.memory"
    value = "512Mi"
  }
}

resource "helm_release" "grafana" {
  depends_on       = [helm_release.prometheus]
  count            = var.enable_monitoring ? 1 : 0
  name             = "grafana"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "grafana"
  version          = "8.0.2"
  namespace        = "monitoring"
  create_namespace = true
  timeout          = 600
  wait             = false

  set {
    name  = "adminPassword"
    value = "circleguard-grafana"
  }

  set {
    name  = "persistence.enabled"
    value = "false"
  }

  set {
    name  = "datasources.datasources.yaml.Datasources[0].url"
    value = "http://prometheus-server.monitoring.svc.cluster.local:80"
  }

  set {
    name  = "datasources.datasources.yaml.Datasources[0].type"
    value = "prometheus"
  }

  set {
    name  = "datasources.datasources.yaml.Datasources[0].isDefault"
    value = "true"
  }
}

resource "helm_release" "elasticsearch" {
  depends_on       = [helm_release.grafana]
  count            = var.enable_elk ? 1 : 0
  name             = "elasticsearch"
  repository       = "https://helm.elastic.co"
  chart            = "elasticsearch"
  version          = "8.5.1"
  namespace        = "logging"
  create_namespace = true
  timeout          = 900
  wait             = false
}

resource "helm_release" "kibana" {
  depends_on       = [helm_release.elasticsearch]
  count            = var.enable_elk ? 1 : 0
  name             = "kibana"
  repository       = "https://helm.elastic.co"
  chart            = "kibana"
  version          = "8.5.1"
  namespace        = "logging"
  create_namespace = true
  timeout          = 900
  wait             = false
  disable_webhooks = true
}

resource "helm_release" "jaeger" {
  depends_on       = [helm_release.elasticsearch]
  count            = var.enable_jaeger ? 1 : 0
  name             = "jaeger"
  repository       = "https://jaegertracing.github.io/helm-charts"
  chart            = "jaeger"
  version          = "3.0.10"
  namespace        = "tracing"
  create_namespace = true
  wait             = false
}

resource "helm_release" "istio_base" {
  count            = var.enable_istio ? 1 : 0
  name             = "istio-base"
  repository       = "https://istio-release.storage.googleapis.com/charts"
  chart            = "base"
  version          = "1.22.8"
  namespace        = "istio-system"
  create_namespace = true
}

resource "helm_release" "istiod" {
  depends_on       = [helm_release.istio_base]
  count            = var.enable_istio ? 1 : 0
  name             = "istiod"
  repository       = "https://istio-release.storage.googleapis.com/charts"
  chart            = "istiod"
  version          = "1.22.8"
  namespace        = "istio-system"
}

resource "helm_release" "istio_ingress" {
  depends_on       = [helm_release.istiod]
  count            = var.enable_istio ? 1 : 0
  name             = "istio-ingressgateway"
  repository       = "https://istio-release.storage.googleapis.com/charts"
  chart            = "gateway"
  version          = "1.22.8"
  namespace        = "istio-system"
}

resource "helm_release" "kiali" {
  depends_on       = [helm_release.istiod]
  count            = var.enable_istio ? 1 : 0
  name             = "kiali-server"
  repository       = "https://kiali.org/helm-charts"
  chart            = "kiali-server"
  version          = "1.87.0"
  namespace        = "istio-system"
}

resource "helm_release" "chaos_mesh" {
  depends_on       = [helm_release.jaeger]
  count            = var.enable_chaos ? 1 : 0
  name             = "chaos-mesh"
  repository       = "https://charts.chaos-mesh.org"
  chart            = "chaos-mesh"
  version          = "2.7.3"
  namespace        = "chaos-testing"
  create_namespace = true
  wait             = false
}

resource "helm_release" "kubecost" {
  depends_on       = [helm_release.chaos_mesh]
  count            = var.enable_finops ? 1 : 0
  name             = "kubecost"
  repository       = "https://kubecost.github.io/cost-analyzer"
  chart            = "cost-analyzer"
  version          = "2.3.5"
  namespace        = "kubecost"
  create_namespace = true
  timeout          = 900
  wait             = false

  set {
    name  = "prometheus.enabled"
    value = "false"
  }

  set {
    name  = "global.prometheus.fqdn"
    value = "http://prometheus-server.monitoring:9090"
  }
}

resource "helm_release" "keda" {
  count            = var.enable_keda ? 1 : 0
  name             = "keda"
  repository       = "https://kedacore.github.io/charts"
  chart            = "keda"
  version          = "2.14.3"
  namespace        = "keda"
  create_namespace = true
}
