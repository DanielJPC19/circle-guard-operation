# CircleGuard — Operations Repository

Manifests de Kubernetes, Terraform multi-cloud y pipelines de CD para CircleGuard.

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
