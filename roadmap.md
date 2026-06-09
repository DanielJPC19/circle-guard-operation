# CircleGuard — Roadmap Unificado

**Deadline:** 12 de junio de 2026 | **Sprints:** 2 iteraciones de ~9 y ~8 días  
**Meta:** 120% (100% requerimientos base + 20% bonus completos)

---

## Tabla de Contenidos

1. [Síntesis: Lo Mejor de Ambos Proyectos](#1-síntesis-lo-mejor-de-ambos-proyectos)
2. [Decisiones de Arquitectura Base](#2-decisiones-de-arquitectura-base)
3. [Construcción de Imágenes Docker](#3-construcción-de-imágenes-docker)
4. [Pipeline CI/CD Híbrido](#4-pipeline-cicd-híbrido-github-actions--jenkins)
5. [Infraestructura como Código — Terraform Multi-cloud](#5-infraestructura-como-código--terraform-multi-cloud)
6. [Kubernetes y Orquestación](#6-kubernetes-y-orquestación)
7. [Seguridad](#7-seguridad)
8. [Observabilidad y Monitoreo](#8-observabilidad-y-monitoreo)
9. [Testing Completo](#9-testing-completo)
10. [Patrones de Diseño](#10-patrones-de-diseño)
11. [Bonus: Multi-cloud (5%)](#11-bonus-multi-cloud-5)
12. [Bonus: Service Mesh — Istio (5%)](#12-bonus-service-mesh--istio-5)
13. [Bonus: Chaos Engineering — Chaos Mesh (5%)](#13-bonus-chaos-engineering--chaos-mesh-5)
14. [Bonus: FinOps — Kubecost + KEDA (5%)](#14-bonus-finops--kubecost--keda-5)
15. [Roadmap por Iteraciones](#15-roadmap-por-iteraciones)

---

## 1. Síntesis: Lo Mejor de Ambos Proyectos

El proyecto unificado toma las decisiones más sólidas de cada implementación existente y descarta las inconsistencias.

### Conservar del Monorepo (`circle-guard-public`)

| Elemento | Razón |
|---|---|
| Estructura k8s con 3 namespaces (`dev`/`stage`/`prod`) + NetworkPolicy + ServiceAccount | Aislamiento correcto entre ambientes en el mismo cluster |
| `HEALTHCHECK` en Dockerfile | Falla rápido en docker-compose y en k8s readiness |
| HPA en stage y prod | Escalado automático ya definido y probado |
| Pod Anti-Affinity en prod (preferred) | Alta disponibilidad real en nodos distintos |
| Separación `k8s/infra/` vs `k8s/services/` | Claridad entre infraestructura y aplicación |
| ConfigMap dual (`service-config` + `infra-config`) | Cada deployment recibe URLs de infra del namespace |
| Probes de salud en todos los servicios (`/actuator/health`) | Convergencia con Spring Boot Actuator ya integrado |

### Conservar del Multirepo (`circle-guard-public-development` + `-production`)

| Elemento | Razón |
|---|---|
| `ARG JAR_FILE` en Dockerfiles | Flexible, sin hardcodeo de ruta; la CI descubre el JAR |
| Un único `Jenkinsfile` multi-branch | Menos archivos de CI que mantener |
| Git SHA en tags de imagen (`:prod-a3f9c12`) | Trazabilidad exacta commit ↔ imagen en producción |
| Dry-run server-side antes de `kubectl apply` | Previene errores de YAML silenciosos en k8s |
| Auto-rollback si falla `rollout status` | Producción nunca queda en estado roto |
| Reset de DB en staging antes de deploy | Garantiza migraciones Flyway limpias en cada deploy |
| Generación automática de Release Notes | Trazabilidad de cambios sin esfuerzo manual |
| Git tags semánticos de release (`v{N}`) | Referencia clara a versiones en producción |
| `docker-compose.test.yml` con healthchecks | Integration tests contra servicios reales, no mocks |
| Cross-pipeline orchestration (CI app → CD ops) | Separación de responsabilidades mantenida |

### Descartar de Ambos

| Problema | Origen | Solución |
|---|---|---|
| Discrepancia Docker Hub vs Azure ACR en manifests | Monorepo | ACR como registry único y central |
| Pipeline master incompleto (solo 2/6 servicios) | Monorepo | GitHub Actions construye los 6 servicios |
| Infra triplicada por namespace | Monorepo | Infra compartida o un cluster por ambiente |
| Secrets en base64 versionados en git | Multirepo ops | Sealed Secrets (kubeseal) |
| URL del Jenkins ops hardcodeada en código | Multirepo dev | Variable de entorno en GitHub Actions secrets |
| Fire-and-forget en deploy de producción | Multirepo dev | GHA espera resultado del Jenkins ops |

---

## 2. Decisiones de Arquitectura Base

### Estrategia de Repositorios (Multirepo)

```
circleguard-app/       ← microservicios Java/Kotlin + mobile + CI (GitHub Actions)
circleguard-ops/       ← k8s manifests + Terraform + Helm values + Jenkinsfiles CD
```

**Ventajas:** CI del código separado del CD de infraestructura. Permisos de acceso distintos. Evolución independiente.

### Branching Strategy — GitFlow Adaptado

```
main ──────────────────────────────────────────── (producción: tag v{N})
  │
  ├── release/1.0 ──────────────────────────────── (staging: tag :staging-{SHA})
  │
  └── develop ──────────────────────────────────── (dev: tag :dev-{SHA})
        │
        ├── feature/auth-jwt-refresh
        ├── feature/promotion-cascade
        └── fix/gateway-timeout
```

| Rama | Trigger CI | Ambiente destino | Tag de imagen |
|---|---|---|---|
| `feature/*` | PR check (build + test, sin push) | — | — |
| `develop` | Push | DOKS dev | `:dev-{SHA}` |
| `release/*` | Push | AKS staging | `:staging-{SHA}` |
| `main` | Push | GKE prod | `:prod-{SHA}` + `:latest` + `v{N}` |

### Convención de Namespaces K8s

| Ambiente | Cluster | Namespace |
|---|---|---|
| Development | Digital Ocean (DOKS) | `circleguard-dev` |
| Staging | Azure (AKS) | `circleguard-stage` |
| Production | GCP (GKE) | `circleguard-prod` |

### Registry de Imágenes

**Azure Container Registry (ACR)** como registry central único, accesible desde los 3 clouds.

```
<acr-name>.azurecr.io/circleguard/<service>:<env>-<sha>
# Ejemplos:
cgregistry.azurecr.io/circleguard/circleguard-auth-service:dev-a3f9c12
cgregistry.azurecr.io/circleguard/circleguard-promotion-service:prod-f4e1b90
```

---

## 3. Construcción de Imágenes Docker

### Dockerfile Unificado (aplicado a los 6 servicios con imagen)

```dockerfile
# Stage 1: build (Gradle en CI, no en Docker — se usa ARG JAR_FILE)
FROM eclipse-temurin:21-jre-alpine AS runtime

# Usuario no-root (seguridad)
RUN addgroup -S circleguard && adduser -S circleguard -G circleguard

WORKDIR /app

# JAR path inyectado por la CI en build time
ARG JAR_FILE
COPY ${JAR_FILE} app.jar

# Cambiar propietario del JAR
RUN chown circleguard:circleguard app.jar
USER circleguard

EXPOSE <puerto>

# Health check directo en contenedor
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD wget --quiet --tries=1 --spider http://localhost:<puerto>/actuator/health || exit 1

ENTRYPOINT ["java", \
  "-Djava.security.egd=file:/dev/./urandom", \
  "-XX:+UseContainerSupport", \
  "-XX:MaxRAMPercentage=75.0", \
  "-jar", "app.jar"]
```

**Mejoras respecto a ambos repos:**
- Usuario no-root (`circleguard`) — requerimiento de seguridad
- `-XX:+UseContainerSupport` — JVM respeta los límites de memoria del contenedor k8s
- `-XX:MaxRAMPercentage=75.0` — previene OOMKilled
- `-Djava.security.egd=file:/dev/./urandom` — acelera arranque en contenedor
- `ARG JAR_FILE` flexible (del multirepo)
- `HEALTHCHECK` integrado (del monorepo)

### Descubrimiento del JAR en CI

```bash
# En GitHub Actions (ci-develop.yml)
JAR=$(find services/circleguard-${SERVICE}/build/libs -name "*.jar" ! -name "*-plain.jar" | head -1)
docker build \
  -f services/circleguard-${SERVICE}/Dockerfile \
  --build-arg JAR_FILE=${JAR} \
  -t ${ACR_REGISTRY}/circleguard/${SERVICE}:${ENV}-${SHORT_SHA} \
  --label "git.sha=${GITHUB_SHA}" \
  --label "git.branch=${GITHUB_REF_NAME}" \
  --label "build.date=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  .
```

---

## 4. Pipeline CI/CD Híbrido (GitHub Actions + Jenkins)

```
┌──────────────────────────────────────────────────────────────────────────┐
│                    GITHUB ACTIONS (repo: circleguard-app)                │
│                                                                          │
│  develop → ci-develop.yml                                                │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │ Checkout → Gradle Build → Unit Tests → SonarQube Quality Gate    │   │
│  │ → Trivy Scan → Docker Build → Push ACR (:dev-{SHA})              │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                          │ Slack/Teams notification                      │
│                                                                          │
│  release/* → ci-release.yml                                             │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │ Checkout → Build → Unit Tests → Integration Tests                │   │
│  │ → SonarQube → Trivy → Docker Build → Push ACR (:staging-{SHA})  │   │
│  │ → HTTP POST Jenkins Staging (espera hasta 30 min)               │   │
│  │ → E2E Tests (port-forward a circleguard-stage AKS)              │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  main → ci-main.yml                                                      │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │ Checkout → Build → Unit + Integration Tests                      │   │
│  │ → SonarQube → Trivy → OWASP ZAP (DAST contra staging)           │   │
│  │ → Docker Build → Push ACR (:prod-{SHA} + :latest)               │   │
│  │ → Locust Performance Tests                                        │   │
│  │ → Release Notes (git log + JaCoCo report)                        │   │
│  │ → APROBACIÓN MANUAL (GitHub Environments, timeout 1h)           │   │
│  │ → HTTP POST Jenkins Prod (espera resultado)                      │   │
│  │ → Git tag v{MAJOR}.{MINOR}.{PATCH} (semantic versioning)        │   │
│  └──────────────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────────┘
                    │                              │
          Jenkins Staging                    Jenkins Prod
    (repo: circleguard-ops)            (repo: circleguard-ops)
┌─────────────────────────┐      ┌──────────────────────────────┐
│ Jenkinsfile-staging      │      │ Jenkinsfile-prod              │
│                          │      │                               │
│ Auth AKS cluster         │      │ Auth GKE cluster              │
│ Create namespace (idem.) │      │ Create namespace (idem.)      │
│ Deploy infra middleware   │      │ Deploy infra middleware        │
│ Validate (dry-run)        │      │ Validate (dry-run)            │
│ kubeseal update tags      │      │ kubeseal update tags          │
│ Apply Secrets             │      │ Apply Secrets                 │
│ Reset Stage DB            │      │ (no DB reset en prod)         │
│ kubectl apply stage/      │      │ kubectl apply prod/           │
│ Rollout verify            │      │ Rollout verify                │
│ Auto-rollback si falla    │      │ Auto-rollback si falla        │
│ Health check (LB IP)      │      │ Health check (LB IP)          │
│                          │      │ Release Notes → GitHub Rel.   │
└─────────────────────────┘      └──────────────────────────────┘
```

### GitHub Actions — Variables y Secrets

```yaml
# Secrets en GitHub (Settings → Secrets → Actions)
ACR_LOGIN_SERVER:     cgregistry.azurecr.io
ACR_USERNAME:         (service principal Azure)
ACR_PASSWORD:         (service principal Azure)
SONARQUBE_URL:        https://sonar.circleguard.internal
SONARQUBE_TOKEN:      (token SonarQube)
JENKINS_STAGING_URL:  https://jenkins-ops.circleguard.internal
JENKINS_PROD_URL:     https://jenkins-ops.circleguard.internal
JENKINS_TOKEN:        (API token Jenkins)
GH_TOKEN:             (GitHub token para tags)
SLACK_WEBHOOK:        (notificaciones)
```

### Versionado Semántico Automático

```bash
# En ci-main.yml: determinar versión basado en commits desde último tag
LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
COMMITS=$(git log ${LAST_TAG}..HEAD --oneline)

if echo "$COMMITS" | grep -q "BREAKING CHANGE\|feat!:"; then
  # Major bump
elif echo "$COMMITS" | grep -q "^feat"; then
  # Minor bump
else
  # Patch bump
fi
NEW_TAG="v${MAJOR}.${MINOR}.${PATCH}"
git tag ${NEW_TAG}
git push origin ${NEW_TAG}
```

---

## 5. Infraestructura como Código — Terraform Multi-cloud

### Estructura de Módulos

```
circleguard-ops/
└── infra/
    ├── modules/
    │   ├── doks/                    # Digital Ocean Kubernetes (dev)
    │   │   ├── main.tf              # digitalocean_kubernetes_cluster
    │   │   ├── variables.tf
    │   │   └── outputs.tf           # cluster endpoint, kubeconfig
    │   ├── aks/                     # Azure Kubernetes Service (staging)
    │   │   ├── main.tf              # azurerm_kubernetes_cluster
    │   │   ├── variables.tf
    │   │   └── outputs.tf
    │   ├── gke/                     # GCP Google Kubernetes Engine (prod)
    │   │   ├── main.tf              # google_container_cluster
    │   │   ├── variables.tf
    │   │   └── outputs.tf
    │   ├── acr/                     # Azure Container Registry (compartido)
    │   │   ├── main.tf              # azurerm_container_registry
    │   │   └── outputs.tf
    │   └── k8s-addons/              # Helm releases en cualquier cluster
    │       ├── main.tf              # cert-manager, Prometheus, Grafana,
    │       │                        # ELK, Jaeger, Istio, Chaos Mesh,
    │       │                        # Kubecost, KEDA, SonarQube
    │       ├── variables.tf
    │       └── outputs.tf
    └── envs/
        ├── dev/
        │   ├── main.tf              # llama módulo doks + k8s-addons (subset)
        │   ├── terraform.tfvars
        │   └── backend.tf           # backend: DO Spaces (S3-compatible)
        ├── staging/
        │   ├── main.tf              # llama módulo aks + acr + k8s-addons
        │   ├── terraform.tfvars
        │   └── backend.tf           # backend: Azure Blob Storage
        └── prod/
            ├── main.tf              # llama módulo gke + k8s-addons (full)
            ├── terraform.tfvars
            └── backend.tf           # backend: GCS bucket
```

### Módulo DOKS (Digital Ocean — Dev)

```hcl
# modules/doks/main.tf
terraform {
  required_providers {
    digitalocean = { source = "digitalocean/digitalocean", version = "~> 2.0" }
  }
}

resource "digitalocean_kubernetes_cluster" "dev" {
  name    = "circleguard-dev"
  region  = var.region          # "nyc1"
  version = "1.32.x-do.0"

  node_pool {
    name       = "worker"
    size       = "s-2vcpu-4gb"  # ~$24/mes por nodo
    node_count = 2
    auto_scale = true
    min_nodes  = 1
    max_nodes  = 3
  }
}
```

### Módulo AKS (Azure — Staging)

```hcl
# modules/aks/main.tf
resource "azurerm_kubernetes_cluster" "staging" {
  name                = "circleguard-stage"
  location            = var.location        # "eastus"
  resource_group_name = var.resource_group
  dns_prefix          = "cg-stage"
  kubernetes_version  = "1.32"

  default_node_pool {
    name       = "system"
    node_count = 2
    vm_size    = "Standard_D2s_v3"
    enable_auto_scaling = true
    min_count  = 1
    max_count  = 4
  }

  identity { type = "SystemAssigned" }

  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.staging.id
  }
}

# ACR pull permissions para AKS
resource "azurerm_role_assignment" "aks_acr" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.staging.kubelet_identity[0].object_id
}
```

### Módulo GKE (GCP — Prod)

```hcl
# modules/gke/main.tf
resource "google_container_cluster" "prod" {
  name                     = "circleguard-prod"
  location                 = var.region         # "us-central1"
  remove_default_node_pool = true
  initial_node_count       = 1
  deletion_protection      = true               # protección en prod

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }
}

resource "google_container_node_pool" "prod_nodes" {
  name       = "prod-pool"
  cluster    = google_container_cluster.prod.name
  location   = var.region
  node_count = 3

  autoscaling {
    min_node_count = 2
    max_node_count = 8
  }

  node_config {
    machine_type = "e2-standard-4"
    disk_size_gb = 50
    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]
    workload_metadata_config { mode = "GKE_METADATA" }
  }
}
```

### Módulo k8s-addons (Helm releases via Terraform)

```hcl
# modules/k8s-addons/main.tf — instalados según variable enable_*
resource "helm_release" "cert_manager" {
  count      = var.enable_cert_manager ? 1 : 0
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = "~> 1.15"
  namespace  = "cert-manager"
  create_namespace = true
  set { name = "installCRDs"; value = "true" }
}

resource "helm_release" "prometheus_stack" {
  count      = var.enable_monitoring ? 1 : 0
  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "~> 61.0"
  namespace  = "monitoring"
  create_namespace = true
}

resource "helm_release" "istio_base" {
  count      = var.enable_istio ? 1 : 0
  name       = "istio-base"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "base"
  version    = "~> 1.22"
  namespace  = "istio-system"
  create_namespace = true
}

resource "helm_release" "istiod" {
  depends_on = [helm_release.istio_base]
  count      = var.enable_istio ? 1 : 0
  name       = "istiod"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "istiod"
  version    = "~> 1.22"
  namespace  = "istio-system"
}

resource "helm_release" "chaos_mesh" {
  count      = var.enable_chaos ? 1 : 0
  name       = "chaos-mesh"
  repository = "https://charts.chaos-mesh.org"
  chart      = "chaos-mesh"
  version    = "~> 2.7"
  namespace  = "chaos-testing"
  create_namespace = true
}

resource "helm_release" "kubecost" {
  count      = var.enable_finops ? 1 : 0
  name       = "kubecost"
  repository = "https://kubecost.github.io/cost-analyzer"
  chart      = "cost-analyzer"
  version    = "~> 2.3"
  namespace  = "kubecost"
  create_namespace = true
}
```

### Backends Remotos por Ambiente

```hcl
# envs/dev/backend.tf
terraform {
  backend "s3" {                      # DO Spaces es S3-compatible
    endpoint = "nyc3.digitaloceanspaces.com"
    bucket   = "circleguard-tfstate"
    key      = "dev/terraform.tfstate"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    force_path_style            = true
    region   = "us-east-1"            # requerido pero ignorado
  }
}

# envs/staging/backend.tf
terraform {
  backend "azurerm" {
    resource_group_name  = "circleguard-tfstate-rg"
    storage_account_name = "cgtfstate"
    container_name       = "tfstate"
    key                  = "staging/terraform.tfstate"
  }
}

# envs/prod/backend.tf
terraform {
  backend "gcs" {
    bucket = "circleguard-tfstate"
    prefix = "prod/terraform.tfstate"
  }
}
```

---

## 6. Kubernetes y Orquestación

### Estructura de Manifests (repo circleguard-ops)

```
circleguard-ops/
└── k8s/
    ├── namespaces/
    │   ├── circleguard-dev.yml     # Namespace + NetworkPolicy + ServiceAccount + RBAC
    │   ├── circleguard-stage.yml
    │   └── circleguard-prod.yml
    ├── infra/                      # Middleware (aplica igual en los 3 ambientes)
    │   ├── postgres.yml
    │   ├── neo4j.yml               # con APOC plugin
    │   ├── kafka.yml               # + Zookeeper
    │   ├── redis.yml
    │   └── configmap-infra.yml     # DNS interno por namespace
    ├── secrets/                    # Sealed Secrets (kubeseal)
    │   ├── sealed-secret-dev.yml
    │   ├── sealed-secret-stage.yml
    │   └── sealed-secret-prod.yml
    └── services/
        ├── dev/                    # 1 réplica, tag :dev-{SHA}
        │   ├── auth-service.yml
        │   └── ... (5 más)
        ├── stage/                  # 2 réplicas + HPA
        │   └── all-services.yml    # consolidado
        └── prod/                   # 2 réplicas + HPA + anti-affinity + PDB
            └── all-services.yml
```

### Configuración por Ambiente

| Recurso K8s | DEV | STAGE | PROD |
|---|---|---|---|
| Réplicas | 1 | 2 | 2 (escala con HPA) |
| HPA minReplicas | — | 2 | 2 |
| HPA maxReplicas | — | 4 | 8 |
| CPU target HPA | — | 70% | 60% |
| Pod Anti-Affinity | No | No | Sí (preferred) |
| PodDisruptionBudget | No | No | minAvailable: 1 |
| RAM requests / limits | 64Mi / 256Mi | 256Mi / 512Mi | 512Mi / 1Gi |
| CPU requests / limits | 50m / 200m | 250m / 500m | 500m / 1000m |
| Log level | DEBUG | INFO | WARN |

### Sealed Secrets (reemplaza base64 en git)

```bash
# Instalar kubeseal CLI
brew install kubeseal

# Generar sealed secret para staging
kubectl create secret generic circleguard-secret \
  --from-literal=POSTGRES_PASSWORD=<real_pass> \
  --from-literal=JWT_SECRET=<real_jwt> \
  --dry-run=client -o yaml | \
  kubeseal --controller-name=sealed-secrets \
           --controller-namespace=kube-system \
           --format yaml > k8s/secrets/sealed-secret-stage.yml
# El archivo YML resultante es SEGURO de versionar en git
```

### Ingress con TLS (cert-manager + Let's Encrypt)

```yaml
# k8s/services/stage/ingress.yml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: circleguard-ingress
  namespace: circleguard-stage
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  tls:
  - hosts:
    - api-stage.circleguard.edu
    secretName: circleguard-tls-stage
  rules:
  - host: api-stage.circleguard.edu
    http:
      paths:
      - path: /api/v1/auth
        pathType: Prefix
        backend:
          service: { name: auth-service, port: { number: 8180 } }
      - path: /api/v1/gate
        pathType: Prefix
        backend:
          service: { name: gateway-service, port: { number: 8087 } }
```

### RBAC por Namespace

```yaml
# Rol para developers: read-only en dev, sin acceso a prod
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: developer-role
  namespace: circleguard-dev
rules:
- apiGroups: [""]
  resources: ["pods", "services", "configmaps"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "list", "watch"]
---
# Rol para CI/CD pipeline: deploy en staging y prod
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: cicd-deployer
  namespace: circleguard-prod
rules:
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "list", "update", "patch"]
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch"]
```

---

## 7. Seguridad

### SonarQube — Análisis Estático (SAST)

```yaml
# En ci-develop.yml
- name: SonarQube Analysis
  run: |
    ./gradlew sonarqube \
      -Dsonar.projectKey=circleguard \
      -Dsonar.host.url=${{ secrets.SONARQUBE_URL }} \
      -Dsonar.login=${{ secrets.SONARQUBE_TOKEN }} \
      -Dsonar.coverage.jacoco.xmlReportPaths=**/build/reports/jacoco/test/jacocoTestReport.xml

- name: SonarQube Quality Gate
  uses: sonarsource/sonarqube-quality-gate-action@master
  with:
    scanMetadataReportFile: .scannerwork/report-task.txt
  env:
    SONAR_TOKEN: ${{ secrets.SONARQUBE_TOKEN }}
```

**Quality Gate configurado:** cobertura > 70%, 0 bugs críticos, 0 vulnerabilidades críticas.

### Trivy — Escaneo de Vulnerabilidades de Contenedor

```yaml
- name: Trivy Vulnerability Scan
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: ${{ env.ACR_REGISTRY }}/circleguard/${{ env.SERVICE }}:${{ env.SHORT_SHA }}
    format: 'sarif'
    output: 'trivy-results.sarif'
    severity: 'CRITICAL,HIGH'
    exit-code: '1'           # Falla el pipeline si hay vulns CRITICAL

- name: Upload Trivy results to GitHub Security
  uses: github/codeql-action/upload-sarif@v3
  with:
    sarif_file: 'trivy-results.sarif'
```

### OWASP ZAP — Pruebas de Seguridad Dinámicas (DAST)

```yaml
# Solo en ci-main.yml (antes de deploy a prod)
- name: OWASP ZAP Scan
  uses: zaproxy/action-full-scan@v0.10.0
  with:
    target: 'https://api-stage.circleguard.edu'
    rules_file_name: '.zap/rules.tsv'
    cmd_options: '-a'
    fail_action: true
    artifact_name: 'zap-report'
```

### Sealed Secrets — Gestión de Credenciales

Ver sección 6. Los secrets nunca se almacenan en texto plano o base64 en git. El controlador de Sealed Secrets los descifra en runtime usando la clave privada del cluster.

---

## 8. Observabilidad y Monitoreo

### Stack Completo

```
┌─────────────────────────────────────────────────────────────────┐
│                     OBSERVABILIDAD                               │
│                                                                 │
│  Métricas:                                                       │
│  Spring Boot Actuator → Prometheus → Grafana Dashboards         │
│  (por servicio: JVM, HTTP requests, Kafka lag, Neo4j, Redis)    │
│                                                                 │
│  Logs:                                                          │
│  App → Logstash → Elasticsearch → Kibana                        │
│  (formato JSON estructurado, nivel configurable por namespace)  │
│                                                                 │
│  Trazas:                                                        │
│  Spring Sleuth → Jaeger (OpenTelemetry)                         │
│  (trace ID propagado entre todos los servicios)                 │
│                                                                 │
│  Service Mesh (Istio):                                          │
│  Envoy sidecars → Prometheus → Kiali (topology view)            │
│                                                                 │
│  Alertas (Alertmanager → Slack + PagerDuty):                    │
│  - Pod CrashLoopBackOff > 2 veces en 5 min                     │
│  - Latencia P99 > 2 segundos                                    │
│  - Kafka consumer lag > 1000 mensajes                           │
│  - Neo4j heap > 85%                                             │
│  - Deployment que no completa rollout en 5 min                  │
└─────────────────────────────────────────────────────────────────┘
```

### Prometheus + Grafana

Instalados vía `kube-prometheus-stack` (Helm). Dashboards predefinidos:
- **JVM Overview** — heap, GC, threads (por servicio)
- **Spring Boot** — HTTP request rate, error rate, latencia P50/P95/P99
- **Kafka** — producer/consumer throughput, lag por topic
- **Neo4j** — query time, connection pool, heap
- **Business metrics** — status promotions/min, active circles, fence activations

### ELK Stack

```yaml
# Configuración Logstash para parsear logs JSON de Spring Boot
input {
  beats { port => 5044 }
}
filter {
  json { source => "message" }
  mutate {
    add_field => { "service" => "%{[spring][application][name]}" }
    add_field => { "trace_id" => "%{[logging][pattern][level]}" }
  }
}
output {
  elasticsearch {
    hosts => ["elasticsearch:9200"]
    index => "circleguard-%{service}-%{+YYYY.MM.dd}"
  }
}
```

### Jaeger — Distributed Tracing

```yaml
# application.yml — habilitado en todos los servicios
spring:
  sleuth:
    enabled: true
    sampler:
      probability: 1.0           # 100% en dev/stage, 10% en prod
  zipkin:
    base-url: http://jaeger-collector:9411
    sender:
      type: web
```

---

## 9. Testing Completo

### Pirámide de Testing

```
         ┌─────────────┐
         │  Security   │  OWASP ZAP (DAST) — solo en main
         │   Tests     │
        ┌┴─────────────┴┐
        │  Performance  │  Locust (30→100 users, 5% error threshold)
        │    Tests      │
       ┌┴───────────────┴┐
       │   E2E Tests      │  (port-forward a staging cluster, solo release/*)
      ┌┴─────────────────┴┐
      │ Integration Tests  │  docker-compose.test.yml + Testcontainers
     ┌┴───────────────────┴┐
     │     Unit Tests       │  JUnit 5 + Mockito (todas las ramas)
     └─────────────────────┘
```

### Cobertura — JaCoCo

```kotlin
// build.gradle.kts (root)
subprojects {
    apply(plugin = "jacoco")

    tasks.jacocoTestReport {
        reports {
            xml.required.set(true)
            html.required.set(true)
        }
    }

    tasks.jacocoTestCoverageVerification {
        violationRules {
            rule {
                limit {
                    minimum = "0.70".toBigDecimal()   // 70% mínimo
                }
            }
        }
    }

    tasks.check { dependsOn(tasks.jacocoTestCoverageVerification) }
}
```

### Locust Performance Tests

```python
# tests/performance/locustfile.py
from locust import HttpUser, task, between

class CircleGuardUser(HttpUser):
    wait_time = between(1, 3)

    def on_start(self):
        response = self.client.post("/api/v1/auth/login", json={
            "username": "testuser", "password": "password"
        })
        self.token = response.json()["token"]

    @task(3)
    def check_health_status(self):
        self.client.get("/api/v1/health-status/me",
            headers={"Authorization": f"Bearer {self.token}"})

    @task(1)
    def submit_questionnaire(self):
        self.client.get("/api/v1/questionnaires",
            headers={"Authorization": f"Bearer {self.token}"})
```

```bash
# Ejecución en CI:
locust -f tests/performance/locustfile.py \
  --host=https://api-stage.circleguard.edu \
  --users=50 --spawn-rate=5 --run-time=5m \
  --headless --csv=results/locust \
  --exit-code-on-error 1
```

### Integración Testing en CI

| Test type | Rama trigger | Herramienta | Bloqueante |
|---|---|---|---|
| Unit | Todas | JUnit 5 + Mockito | Sí |
| Coverage | Todas | JaCoCo (min 70%) | Sí |
| SAST | Todas | SonarQube Quality Gate | Sí |
| Container scan | Todas | Trivy (CRITICAL/HIGH) | Sí |
| Integration | `release/*` + `main` | Testcontainers | Sí |
| E2E | `release/*` | TestRestTemplate | Sí |
| Performance | `main` | Locust | Sí (max 5% errors) |
| DAST | `main` | OWASP ZAP | Sí |

---

## 10. Patrones de Diseño

### Patrones Existentes (documentar)

| Patrón | Dónde en CircleGuard |
|---|---|
| Repository | `*Repository` interfaces en todos los servicios |
| Factory | `DualChainAuthenticationProvider` (auth-service) |
| Observer | `SurveyListener` → Kafka consumer (promotion-service) |
| Decorator | `JwtAuthenticationFilter` wraps Spring Security chain |

### Patrones a Implementar

#### 1. Circuit Breaker — vía Istio (reemplaza Resilience4j)

```yaml
# DestinationRule con circuit breaker para identity-service
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: identity-service-cb
  namespace: circleguard-prod
spec:
  host: identity-service
  trafficPolicy:
    outlierDetection:
      consecutive5xxErrors: 5
      interval: 30s
      baseEjectionTime: 30s
      maxEjectionPercent: 50
    connectionPool:
      http:
        http1MaxPendingRequests: 100
        http2MaxRequests: 1000
```

#### 2. External Configuration

```yaml
# Configuración externalizada en ConfigMap (ya implementado, mejorar con Vault)
# ConfigMap: fuente única de verdad para URLs de infra
# Sealed Secrets: fuente única de verdad para credentials
# Spring Profiles: dev/stage/prod en application-{profile}.yml
```

#### 3. Saga Pattern (nuevo — en promotion-service)

Para la cascada de promoción de status (Suspect → Probable → Confirmed):
- Cada step de la saga publica un evento en Kafka
- Cada servicio afectado consume y procesa de forma idempotente
- Compensación: si la notificación falla, se registra para reintento

---

## 11. Bonus: Multi-cloud (5%)

### Estrategia de 3 Clouds

| Cloud | Proveedor | Ambiente | Cluster | Costo est. |
|---|---|---|---|---|
| Digital Ocean | DOKS | Desarrollo | 2 nodos `s-2vcpu-4gb` | ~$48/mes |
| Azure | AKS | Staging | 2 nodos `Standard_D2s_v3` | ~$140/mes |
| GCP | GKE | Producción | 3 nodos `e2-standard-4` | ~$230/mes |

### Registry Central — Azure ACR

ACR es accesible desde los 3 clouds:
- **DOKS:** imagePullSecrets con token ACR
- **AKS:** Azure Managed Identity con rol AcrPull (sin secrets en manifests)
- **GKE:** Workload Identity + pull secret generado por Terraform

### Load Balancing entre Clouds (DNS Weighted Routing)

```
api.circleguard.edu
├── api-prod.circleguard.edu    → GKE prod LoadBalancer (weight: 80%)
└── api-stage.circleguard.edu  → AKS staging LoadBalancer (weight: 20%)
```

(Para la demo, se muestra conmutación manual entre clouds)

### Comparativa Documentada

| Métrica | GCP GKE | Azure AKS | Digital Ocean DOKS |
|---|---|---|---|
| Costo nodo comparable | ~$0.14/h | ~$0.10/h | ~$0.036/h |
| Tiempo de provisión cluster | ~8 min | ~12 min | ~5 min |
| Integración ACR | Pull secret | Native (MSI) | Pull secret |
| SLA control plane | 99.95% | 99.95% | 99.5% |

---

## 12. Bonus: Service Mesh — Istio (5%)

### Instalación vía Terraform k8s-addons

```hcl
# Orden de instalación crítico:
# 1. istio-base (CRDs)
# 2. istiod (control plane)
# 3. istio-ingressgateway
# 4. kiali
```

### mTLS Estricto entre Todos los Servicios

```yaml
# Habilitar mTLS STRICT en el namespace de producción
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: circleguard-prod
spec:
  mtls:
    mode: STRICT
```

### Canary Deployment — Traffic Shifting

```yaml
# VirtualService: 80% v1, 20% v2 (canary del promotion-service)
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: promotion-service
  namespace: circleguard-prod
spec:
  hosts: ["promotion-service"]
  http:
  - route:
    - destination:
        host: promotion-service
        subset: v1
      weight: 80
    - destination:
        host: promotion-service
        subset: v2        # nueva versión en canary
      weight: 20
---
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: promotion-service
  namespace: circleguard-prod
spec:
  host: promotion-service
  subsets:
  - name: v1
    labels: { version: "v1" }
  - name: v2
    labels: { version: "v2" }
```

### Visualización con Kiali

```bash
# Port-forward Kiali dashboard
kubectl port-forward svc/kiali 20001:20001 -n istio-system
# Acceder en: http://localhost:20001
```

Kiali muestra:
- Grafo de tráfico entre microservicios en tiempo real
- Métricas de latencia y error rate por conexión
- Configuración de VirtualServices y DestinationRules

### Retry Policies

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: identity-service
spec:
  http:
  - retries:
      attempts: 3
      perTryTimeout: 2s
      retryOn: 5xx,reset,connect-failure
    timeout: 8s
    route:
    - destination:
        host: identity-service
```

---

## 13. Bonus: Chaos Engineering — Chaos Mesh (5%)

### Instalación

```hcl
# Via Terraform k8s-addons (solo en staging)
resource "helm_release" "chaos_mesh" {
  name       = "chaos-mesh"
  repository = "https://charts.chaos-mesh.org"
  chart      = "chaos-mesh"
  namespace  = "chaos-testing"
}
```

### Experimento 1: PodChaos — Kill Aleatorio

```yaml
# Mata un pod aleatorio del promotion-service cada 2 minutos
apiVersion: chaos-mesh.org/v1alpha1
kind: PodChaos
metadata:
  name: promotion-pod-kill
  namespace: chaos-testing
spec:
  action: pod-kill
  mode: one
  selector:
    namespaces: ["circleguard-stage"]
    labelSelectors:
      app: promotion-service
  scheduler:
    cron: "@every 2m"
```

**Resultado esperado:** HPA reprograma el pod en < 30 segundos. Readiness probe previene tráfico hasta que el pod esté listo.

### Experimento 2: NetworkChaos — Latencia entre Servicios

```yaml
# Agrega 500ms de latencia entre auth-service e identity-service
apiVersion: chaos-mesh.org/v1alpha1
kind: NetworkChaos
metadata:
  name: auth-to-identity-delay
  namespace: chaos-testing
spec:
  action: delay
  mode: all
  selector:
    namespaces: ["circleguard-stage"]
    labelSelectors:
      app: auth-service
  delay:
    latency: "500ms"
    jitter: "100ms"
  direction: to
  target:
    selector:
      namespaces: ["circleguard-stage"]
      labelSelectors:
        app: identity-service
  duration: "5m"
```

**Resultado esperado:** Istio retry policy absorbe el 1er timeout. Circuit breaker actúa si la latencia supera el threshold.

### Experimento 3: StressChaos — CPU/Mem Saturation

```yaml
# Satura CPU del neo4j pod para probar el HPA
apiVersion: chaos-mesh.org/v1alpha1
kind: StressChaos
metadata:
  name: neo4j-cpu-stress
  namespace: chaos-testing
spec:
  mode: one
  selector:
    namespaces: ["circleguard-stage"]
    labelSelectors:
      app: neo4j
  stressors:
    cpu:
      workers: 4
      load: 90
  duration: "3m"
```

**Resultado esperado:** HPA del promotion-service (que usa Neo4j) escala ante incremento de latencia. Alertas Prometheus se disparan.

### Integración en Pipeline

```yaml
# En ci-release.yml, post-deploy a staging:
- name: Run Chaos Experiments
  run: |
    kubectl apply -f k8s/chaos/ -n chaos-testing
    sleep 300  # 5 minutos de experimentos
    # Verificar que todos los pods siguen Running
    kubectl get pods -n circleguard-stage
    kubectl delete -f k8s/chaos/ -n chaos-testing
```

---

## 14. Bonus: FinOps — Kubecost + KEDA (5%)

### Kubecost — Monitoreo de Costos

```hcl
# Terraform k8s-addons
resource "helm_release" "kubecost" {
  name       = "kubecost"
  repository = "https://kubecost.github.io/cost-analyzer"
  chart      = "cost-analyzer"
  namespace  = "kubecost"
  set {
    name  = "prometheus.enabled"
    value = "false"                # Usa el Prometheus ya instalado
  }
  set {
    name  = "global.prometheus.fqdn"
    value = "http://kube-prometheus-stack-prometheus.monitoring:9090"
  }
}
```

Kubecost proporciona:
- Costo por namespace (`circleguard-dev`, `circleguard-stage`, `circleguard-prod`)
- Costo por deployment (auth-service, promotion-service, etc.)
- Proyección mensual y comparativa entre clouds

### KEDA — Scale to Zero en Dev

```yaml
# ScaledObject: escala promotion-service a 0 si Kafka lag = 0 fuera de horario
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: promotion-scaler
  namespace: circleguard-dev
spec:
  scaleTargetRef:
    name: promotion-service
  minReplicaCount: 0        # scale to zero en dev
  maxReplicaCount: 3
  triggers:
  - type: kafka
    metadata:
      bootstrapServers: kafka-broker.circleguard-dev.svc.cluster.local:9092
      consumerGroup: promotion-service-group
      topic: health-status-events
      lagThreshold: "5"
```

**Ahorro estimado:** ~40% en costos de compute en el ambiente dev (pods apagados en horas no laborales).

### Dashboard FinOps en Grafana

Panel con datos de Kubecost:
- Costo diario/semanal/mensual por ambiente
- Rightsizing recommendations (servicios sobre-provisionados)
- Comparativa de eficiencia entre clouds (costo por request servido)

### Estrategias de Ahorro Implementadas

| Estrategia | Ambiente | Ahorro estimado |
|---|---|---|
| Scale-to-zero con KEDA | Dev | ~40% |
| Spot instances (DO Preemptible) | Dev | ~30% sobre precio regular |
| Committed use discounts | Prod (GKE) | ~20% con 1-year commitment |
| Right-sizing (ajuste requests) | Todos | ~15% eliminando sobre-provisión |

---

## 15. Roadmap por Iteraciones

### Resumen de Pesos y Cobertura

| Componente (Peso) | Sprint 1 | Sprint 2 | Estado |
|---|---|---|---|
| Terraform IaC (20%) | DOKS + AKS módulos | GKE módulo + k8s-addons | Completo |
| Testing (15%) | Unit + SonarQube | Integration + E2E + Locust + ZAP | Completo |
| CI/CD (15%) | GHA CI + Jenkins staging | Jenkins prod + versionado semántico | Completo |
| Documentación (10%) | Estructura repos | Release Notes + video + presentación | Completo |
| Observabilidad (10%) | — | Prometheus + Grafana + ELK + Jaeger | Completo |
| Metodología ágil (10%) | GitFlow + Jira/GitHub Projects | Sprint reviews | Completo |
| Patrones diseño (10%) | Dockerfiles + estructura | Saga + Circuit Breaker (Istio) | Completo |
| Seguridad (5%) | Trivy + Sealed Secrets + RBAC + TLS | OWASP ZAP | Completo |
| Change Management (5%) | Release Notes draft | Git tags + proceso formal | Completo |
| **Bonus Multi-cloud (5%)** | DOKS + AKS | GKE + comparativa | Completo |
| **Bonus Service Mesh (5%)** | — | Istio + mTLS + Kiali + canary | Completo |
| **Bonus Chaos Engineering (5%)** | — | Chaos Mesh 3 experimentos | Completo |
| **Bonus FinOps (5%)** | — | Kubecost + KEDA + dashboard | Completo |

---

### ITERACIÓN 1 — "Foundation & Core DevOps"
**Fechas:** 25 mayo → 2 junio (9 días)  
**Sprint goal:** App desplegada en DOKS (dev) y AKS (staging) con CI/CD completo y seguridad básica.

```
Día 1-2 │ 25-26 mayo │ ESTRUCTURA BASE
├── Crear repos: circleguard-app (fork/clone) + circleguard-ops
├── Configurar GitFlow: branches develop, release/1.0, main
├── Dockerfiles unificados (ARG JAR_FILE + HEALTHCHECK + non-root)
└── Configurar GitHub Actions (estructura de workflows)

Día 3-4 │ 27-28 mayo │ CI PIPELINE
├── ci-develop.yml: Checkout → Gradle build → Unit tests
├── Integrar SonarQube (quality gate)
├── Integrar Trivy (bloquear en CRITICAL)
├── Docker build → push a Azure ACR con tag :dev-{SHA}
└── Notificaciones Slack en fallo

Día 5-6 │ 29-30 mayo │ TERRAFORM + CLUSTERS
├── Módulo DOKS: cluster dev en Digital Ocean
├── Módulo AKS: cluster staging en Azure
├── Módulo ACR: registry central en Azure
├── Backends remotos (DO Spaces + Azure Blob)
└── Provisionar ambos clusters: terraform apply

Día 7-8 │ 31 mayo - 1 jun │ K8S MANIFESTS + SEGURIDAD
├── Namespaces (circleguard-dev + circleguard-stage) + NetworkPolicies + RBAC
├── Infra middleware (Postgres, Neo4j, Kafka, Redis) por namespace
├── Sealed Secrets (kubeseal install + secrets generados)
├── cert-manager + ClusterIssuer Let's Encrypt
├── Ingress con TLS para staging
└── Deploy de los 6 servicios en dev y staging

Día 9 │ 2 junio │ JENKINS CD STAGING
├── Jenkinsfile-staging: dry-run → update tags (SHA) → apply → rollout verify
├── Auto-rollback si rollout falla en 300s
├── Health check post-deploy (curl /actuator/health)
└── ci-release.yml: build + integration tests + push :staging-{SHA} + trigger Jenkins
```

**Criterios de aceptación:**
- [ ] GitHub Actions CI verde en `develop` con SonarQube quality gate y Trivy
- [ ] App accesible en `https://api-stage.circleguard.edu` con HTTPS
- [ ] Sealed Secrets en uso — 0 credenciales en texto plano en git
- [ ] `kubectl rollout undo` funcional ante deploy roto
- [ ] Terraform `plan` sin errores para dev y staging

---

### ITERACIÓN 2 — "Production + All Bonuses"
**Fechas:** 3 junio → 10 junio (8 días)  
**Sprint goal:** Producción en GKE, todos los 4 bonus implementados, observabilidad completa.

```
Día 1-2 │ 3-4 junio │ PRODUCCIÓN + CI MASTER
├── Módulo GKE (Terraform): cluster prod en GCP
├── RBAC GKE + Workload Identity para ACR
├── ci-main.yml: OWASP ZAP → push :prod-{SHA}+:latest → aprobación manual
├── Jenkinsfile-prod: deploy prod → rollout verify → auto-rollback
├── Semantic versioning automático (script en CI)
└── GitHub Release con Release Notes automáticas

Día 3 │ 5 junio │ BONUS: SERVICE MESH (ISTIO)
├── Istio base + istiod vía Terraform k8s-addons (en prod)
├── PeerAuthentication: mTLS STRICT en namespace prod
├── DestinationRule con circuit breaker + outlier detection
├── VirtualService canary 80/20 para promotion-service
├── Retry policies en identity-service y auth-service
└── Kiali instalado y configurado

Día 4 │ 6 junio │ OBSERVABILIDAD PARTE 1
├── kube-prometheus-stack (Prometheus + Grafana) vía Terraform
├── Dashboards: JVM, Spring Boot, Kafka, Neo4j, Business metrics
├── Jaeger (OpenTelemetry) + Spring Sleuth configurado en todos los servicios
└── Alertas Prometheus → Alertmanager → Slack

Día 5 │ 7 junio │ OBSERVABILIDAD PARTE 2 (ELK)
├── Elasticsearch + Logstash + Kibana vía Helm
├── Filebeat en cada nodo (DaemonSet)
├── Pipeline Logstash: parse JSON logs → índices por servicio
└── Kibana dashboards: error rate, request patterns

Día 6 │ 8 junio │ BONUS: CHAOS ENGINEERING
├── Chaos Mesh instalado vía Terraform k8s-addons (en staging)
├── Experimento 1: PodChaos (pod kill de promotion-service)
├── Experimento 2: NetworkChaos (delay 500ms auth→identity)
├── Experimento 3: StressChaos (CPU stress en Neo4j)
├── Ejecución y documentación de resultados
└── Integración en ci-release.yml (post-deploy chaos test)

Día 7 │ 9 junio │ BONUS: FINOPS
├── Kubecost instalado (Helm, integrado con Prometheus existente)
├── KEDA instalado + ScaledObject para promotion-service en dev
├── Dashboard FinOps en Grafana (datos de Kubecost)
├── Análisis costo/performance: GCP vs Azure vs Digital Ocean
└── Documentación de ahorros implementados y proyectados

Día 8 │ 10 junio │ TESTING COMPLETO + MULTI-CLOUD DOC
├── Locust perf tests contra staging (50 users, 5 min)
├── OWASP ZAP validado contra producción
├── JaCoCo coverage report integrado en SonarQube
├── Documentación comparativa multi-cloud (latencia, costos, SLA)
└── Revisión final de todos los criterios de la rúbrica
```

**Criterios de aceptación:**
- [ ] Producción en GKE con HTTPS y HPA funcional
- [ ] Istio: mTLS activo, Kiali mostrando el mesh, canary 80/20 funcional
- [ ] Chaos Mesh: 3 experimentos ejecutados, resultados documentados
- [ ] Kubecost mostrando costos por namespace en los 3 clouds
- [ ] ELK Stack recibiendo y mostrando logs de todos los servicios
- [ ] Locust: < 5% error rate con 50 usuarios concurrentes
- [ ] Comparativa multi-cloud documentada

---

### BUFFER DEMO (11-12 junio)

```
11 junio │ DEMO PREP
├── Grabación video demo (funcionamiento end-to-end, 10-15 min)
├── Preparar slides de presentación (arquitectura, diagramas, métricas)
├── Ensayo flujo de demo:
│   1. Mostrar repos y branching strategy
│   2. Demo CI: push → GitHub Actions → SonarQube → Trivy → Docker push
│   3. Demo CD: Jenkins deploy staging → auto-rollback demo
│   4. Demo Istio: Kiali, canary, mTLS
│   5. Demo Observabilidad: Grafana + Kibana + Jaeger
│   6. Demo Chaos: ejecutar experimento en vivo
│   7. Demo FinOps: Kubecost dashboard
│   8. Demo Multi-cloud: mostrar los 3 clusters activos
└── Verificación final de todos los componentes

12 junio │ ENTREGA
├── Push final a todos los repos
├── Documentación completa revisada
└── Entrega
```

---

## Diagrama de Arquitectura General

```
                        DESARROLLADOR
                             │
                    git push (feature/*)
                             │
              ┌──────────────▼──────────────┐
              │     circleguard-app          │
              │    (GitHub Actions CI)       │
              │                             │
              │  develop → :dev-{SHA}        │
              │  release/* → :staging-{SHA} │
              │  main → :prod-{SHA}+:latest  │
              └──────────────┬──────────────┘
                             │ push image
                             ▼
              ┌──────────────────────────────┐
              │   Azure Container Registry   │
              │   cgregistry.azurecr.io      │
              └──┬────────────┬─────────────┘
                 │            │
        pull     │     pull   │  pull
                 │            │
    ┌────────────▼──┐  ┌──────▼────────────────────┐
    │ Digital Ocean │  │         Azure AKS          │
    │     DOKS      │  │       (staging)            │
    │   (dev env)   │  │  Istio + mTLS + Kiali      │
    │               │  │  Chaos Mesh                │
    │ circleguard-  │  │  Prometheus + Grafana       │
    │ dev namespace │  │  ELK + Jaeger              │
    │               │  │  Kubecost + KEDA           │
    │ KEDA scale-   │  │                            │
    │ to-zero       │  │ circleguard-stage namespace│
    └───────────────┘  └──────────────┬─────────────┘
                                      │
                              Jenkins trigger
                              (IMAGE_TAG={SHA})
                                      │
                       ┌──────────────▼──────────────┐
                       │          GCP GKE             │
                       │        (production)          │
                       │   Istio + mTLS + Kiali       │
                       │   Prometheus + Grafana       │
                       │   ELK + Jaeger               │
                       │   Kubecost                   │
                       │   HPA + Anti-affinity + PDB  │
                       │                             │
                       │  circleguard-prod namespace  │
                       │                             │
                       │  auth:prod-{SHA}             │
                       │  identity:prod-{SHA}         │
                       │  promotion:prod-{SHA}        │
                       │  gateway:prod-{SHA}          │
                       │  notification:prod-{SHA}     │
                       │  form:prod-{SHA}             │
                       └─────────────────────────────┘
```
