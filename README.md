# CircleGuard — Operations Repository

Manifests de Kubernetes, Terraform multi-cloud y pipelines de CD para CircleGuard.

Acceda al informe desde aquí:

https://github.com/DanielJPC19/circle-guard-operation/blob/main/informe-circleguard.md

## Requisitos

- `kubectl` 1.29+
- `terraform` 1.7+
- `kubeseal` (Sealed Secrets CLI)
- `gcloud` CLI (para GKE prod)
- `az` CLI (para AKS staging)
- `doctl` CLI (para DOKS dev)
- `helm` 3.14+

## Estructura

```
circle-guard-operation/
├── k8s/
│   ├── cert-manager/        # ClusterIssuer Let's Encrypt
│   ├── namespaces/          # Namespace + NetworkPolicy + RBAC × 3 ambientes
│   ├── infra/               # Middleware (Postgres, Neo4j, Kafka, Redis, OpenLDAP)
│   ├── configmaps/          # ConfigMaps con DNS interno
│   ├── secrets/             # Sealed Secrets (placeholders — ver workflow abajo)
│   └── services/
│       ├── dev/             # 1 réplica + KEDA ScaledObjects
│       ├── stage/           # 2 réplicas + HPA 2-4
│       └── prod/            # 2 réplicas + HPA 2-8 + podAntiAffinity
├── infra/
│   ├── modules/             # Terraform: doks/ aks/ gke/ acr/ k8s-addons/
│   └── envs/                # dev/ staging/ prod/ — cada uno con backend remoto
├── istio/                   # mTLS + canary deployments + circuit breakers
├── chaos/                   # Chaos Mesh experiments (3 escenarios)
├── Jenkinsfile-staging       # CD pipeline para AKS staging
├── Jenkinsfile-prod          # CD pipeline para GKE prod
└── scripts/
    ├── update-image-tag.sh
    └── setup-sealed-secrets.sh
```

## Setup inicial — Sealed Secrets

**Sealed Secrets** reemplaza los secrets en base64. Los archivos en `k8s/secrets/` son placeholders. Antes del primer deploy:

```bash
# 1. Instalar el controller (ya incluido en Terraform k8s-addons)
# 2. Generar los secrets reales para cada ambiente:
./scripts/setup-sealed-secrets.sh
# El script te pedirá los valores de cada secret y genera los SealedSecret YAML
```

## Terraform — Provisionar infraestructura

Cada ambiente tiene su propio directorio con backend remoto:

```bash
# DEV — Digital Ocean Kubernetes
cd infra/envs/dev
terraform init
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars

# STAGING — Azure AKS
cd infra/envs/staging
az login
terraform init
terraform apply -var-file=terraform.tfvars

# PROD — GCP GKE
cd infra/envs/prod
gcloud auth application-default login
terraform init
terraform apply -var-file=terraform.tfvars
```

## Kubernetes — Deploy manual

```bash
# 1. Aplicar namespace (incluye NetworkPolicy + RBAC)
kubectl apply -f k8s/namespaces/circleguard-dev.yml

# 2. Aplicar cert-manager ClusterIssuer (una vez por cluster)
kubectl apply -f k8s/cert-manager/clusterissuer.yml

# 3. Middleware (SIEMPRE especificar -n <namespace>)
kubectl apply -f k8s/infra/ -n circleguard-dev

# 4. ConfigMaps
kubectl apply -f k8s/configmaps/configmap-infra.yml

# 5. Sealed Secrets (reemplaza los placeholders primero)
kubectl apply -f k8s/secrets/sealed-secret-dev.yml

# 6. Servicios de aplicación
kubectl apply -f k8s/services/dev/ -n circleguard-dev
```

## CD Pipeline — Jenkins

Los Jenkinsfiles reciben `IMAGE_TAG` como parámetro (ej. `dev-a3f9c12`):

| Jenkinsfile | Cluster | Namespace | Trigger |
|---|---|---|---|
| `Jenkinsfile-staging` | AKS (Azure) | circleguard-stage | ci-release.yml GHA |
| `Jenkinsfile-prod` | GKE (GCP) | circleguard-prod | ci-main.yml GHA (con aprobación manual) |

## Istio Service Mesh

```bash
# Aplicar tras instalar Istio (ya en Terraform k8s-addons)
kubectl apply -f istio/peer-authentication.yml
kubectl apply -f istio/destination-rules.yml
kubectl apply -f istio/virtual-services.yml
```

- `peer-authentication.yml` — mTLS STRICT en prod, PERMISSIVE en stage
- `destination-rules.yml` — Circuit breakers (identity, auth) + subsets canary (promotion)
- `virtual-services.yml` — Canary 80/20 para promotion-service + retry policies

## Chaos Engineering

```bash
# Aplicar experimentos (cluster debe tener Chaos Mesh instalado)
kubectl apply -f chaos/pod-chaos.yml       # Kill pods promotion-service cada 2m
kubectl apply -f chaos/network-chaos.yml   # 500ms latency auth→identity
kubectl apply -f chaos/stress-chaos.yml    # CPU/Memory stress en neo4j
```

## Convención de image tags

| Ambiente | Tag | Ejemplo |
|---|---|---|
| dev | `dev-{SHA}` | `cgregistry.azurecr.io/circleguard/circleguard-auth-service:dev-a3f9c12` |
| staging | `staging-{SHA}` | `...auth-service:staging-b4d8e31` |
| prod | `prod-{SHA}` + `latest` | `...auth-service:prod-c5e9f42` |

## Namespaces

| Namespace | Cluster | Ambiente |
|---|---|---|
| `circleguard-dev` | DOKS (Digital Ocean) | Desarrollo |
| `circleguard-stage` | AKS (Azure) | Staging |
| `circleguard-prod` | GKE (GCP) | Producción |

## GitHub Actions Secrets (DEV Repository)

Los siguientes secretos deben configurarse en GitHub para que los workflows de CI/CD funcionen:

| Secret | Descripción | Valor de Ejemplo | Dónde Obtener |
|--------|-------------|------------------|-----------------|
| `ACR_LOGIN_SERVER` | Azure Container Registry URL | `cgregistry.azurecr.io` | Azure Portal → Container Registries |
| `ACR_USERNAME` | Usuario ACR | Service Principal AppID | Azure Portal → Access Keys |
| `ACR_PASSWORD` | Contraseña ACR | Service Principal Password | Azure Portal → Access Keys |
| `SONARQUBE_URL` | SonarQube Server URL | `https://sonarqube.circleguard.io` | SonarQube Admin Panel |
| `SONARQUBE_TOKEN` | SonarQube Authentication Token | Token generado | SonarQube → User → Security → Generate Token |
| `JENKINS_STAGING_URL` | URL Jenkins Staging | `https://jenkins-staging.circleguard.io` | Jenkins Controller URL |
| `JENKINS_PROD_URL` | URL Jenkins Producción | `https://jenkins-prod.circleguard.io` | Jenkins Controller URL |
| `JENKINS_TOKEN` | Jenkins API Token | API token para usuario jenkins-user | Jenkins → Manage Users → jenkins-user → API Token |
| `GH_TOKEN` | GitHub Personal Access Token | PAT con `repo, workflow` scopes | GitHub → Settings → Developer settings → Personal access tokens |
| `SLACK_WEBHOOK` | Slack Webhook URL | `https://hooks.slack.com/services/...` | Slack Workspace → Apps → Incoming Webhooks |
| `AZ_SUBSCRIPTION_ID` | Azure Subscription ID | `12345678-1234-...` | Azure Portal → Subscriptions |

**Setup en GitHub:**
```bash
# En GitHub UI: Settings → Secrets and Variables → Actions → New Repository Secret
# O vía CLI:
gh secret set ACR_LOGIN_SERVER --body "cgregistry.azurecr.io"
gh secret set ACR_USERNAME --body "<SERVICE_PRINCIPAL_ID>"
# ... etc
```

---

## Documentation

Documentación completa de CircleGuard está en la carpeta `docs/`:

| Documento | Propósito | Audiencia |
|-----------|-----------|-----------|
| **[architecture.md](./docs/architecture.md)** | Visión general de la arquitectura multi-cloud con diagramas Mermaid | Architects, SREs, New Team Members |
| **[operations-manual.md](./docs/operations-manual.md)** | Procedimientos operacionales: deploy, rollback, health checks, troubleshooting | DevOps Engineers, SREs, On-Call |
| **[multi-cloud-comparison.md](./docs/multi-cloud-comparison.md)** | Comparativa de proveedores (DOKS vs AKS vs GKE) y estrategia de selección | Engineering Leads, Architects |
| **[change-management.md](./docs/change-management.md)** | Proceso de cambios: commit conventions, quality gates, approvals, rollback | All Engineers, Release Managers |
| **[design-patterns.md](./docs/design-patterns.md)** | Patrones de diseño implementados en CircleGuard | Backend Engineers, Architects |
| **[cost-analysis.md](./docs/cost-analysis.md)** | Análisis de costos y estrategias FinOps | Finance, Engineering Leads |
| **[chaos-results.md](./docs/chaos-results.md)** | Resultados de experimentos de Chaos Mesh para validar resiliencia | SREs, Quality Assurance |

**Start here:** 👉 [architecture.md](./docs/architecture.md) para entender el sistema completo
