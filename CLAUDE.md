# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Operations repository for **CircleGuard** — Kubernetes manifests, Terraform multi-cloud infrastructure, and Jenkins CD pipelines. There is no application source code here; this repo only describes *how* the system is deployed and operated.

## Multi-cloud architecture

| Environment | Cloud | Cluster | Namespace |
|---|---|---|---|
| dev | Digital Ocean (DOKS) | circleguard-dev | `circleguard-dev` |
| staging | Azure (AKS) | circleguard-stage | `circleguard-stage` |
| prod | GCP (GKE) | circleguard-prod | `circleguard-prod` |

Container images are hosted on Azure Container Registry: `cgregicesi.azurecr.io/circleguard/circleguard-<service>`.

Application services: `auth-service` (8180), `identity-service`, `promotion-service`, `gateway-service` (8087), `notification-service`, `form-service`. Middleware: Postgres (StatefulSet), Kafka, Neo4j, Redis, OpenLDAP.

## Terraform — provision infrastructure

Each environment has an independent backend. Always run from the env directory:

```bash
# DEV (Digital Ocean)
cd infra/envs/dev && terraform init && terraform apply -var-file=terraform.tfvars

# STAGING (Azure) — requires az login first
cd infra/envs/staging && az login && terraform init && terraform apply -var-file=terraform.tfvars

# PROD (GCP) — requires gcloud auth first
cd infra/envs/prod && gcloud auth application-default login && terraform init && terraform apply -var-file=terraform.tfvars
```

The `k8s-addons` module installs cluster tooling via Helm. Flags per env:
- **dev**: cert-manager, monitoring, sealed-secrets, keda, finops — no Istio, no Chaos Mesh
- **staging/prod**: toggle `enable_istio` and `enable_chaos` in the respective `main.tf`

## Kubernetes — manual deploy order

Always apply in this sequence (order matters due to dependencies):

```bash
kubectl apply -f k8s/namespaces/circleguard-<env>.yml           # NetworkPolicy + RBAC
kubectl apply -f k8s/cert-manager/clusterissuer.yml             # once per cluster
kubectl apply -f k8s/infra/ -n <namespace>                      # middleware
kubectl apply -f k8s/configmaps/configmap-infra.yml             # internal DNS config
kubectl apply -f k8s/secrets/sealed-secret-<env>.yml            # sealed secrets
kubectl apply -f k8s/services/<env>/ -n <namespace>             # app deployments
```

## Sealed Secrets workflow

Files in `k8s/secrets/` are **placeholders** — never real secrets. Before first deploy, regenerate them:

```bash
./scripts/setup-sealed-secrets.sh <dev|staging|prod>
# Interactive — prompts for each secret value, writes a safe-to-commit SealedSecret YAML
```

Secrets required: `POSTGRES_PASSWORD`, `NEO4J_PASSWORD`, `JWT_SECRET`, `QR_SECRET`, `VAULT_SECRET`, `VAULT_SALT`, `VAULT_HASH_SALT`, `LDAP_MANAGER_PASSWORD`.

## CD Pipelines (Jenkins)

Both Jenkinsfiles are triggered by GitHub Actions and receive `IMAGE_TAG` as a parameter (e.g. `staging-a3f9c12`):

- `Jenkinsfile-staging` → AKS, uses `gcp-service-account-key` credential, applies `k8s/services/stage/`
- `Jenkinsfile-prod` → GKE, uses `gcp-service-account-key-prod` credential, applies `k8s/services/prod/` **and** all Istio manifests

Both pipelines perform auto-rollback (`kubectl rollout undo`) if any deployment fails its rollout timeout. Staging resets all Postgres databases before deploying (fresh Flyway migrations). Prod generates release notes from conventional commits and checks HPAs + PodDisruptionBudgets.

Health check endpoint: `http://<gateway-lb-ip>:8087/actuator/health` (24 retries × 15s after 90s warmup).

## Image tag convention

| Env | Format | Example |
|---|---|---|
| dev | `dev-{SHA}` | `dev-a3f9c12` |
| staging | `staging-{SHA}` | `staging-b4d8e31` |
| prod | `prod-{SHA}` + `latest` | `prod-c5e9f42` |

To update a tag manually in a manifest file:
```bash
bash scripts/update-image-tag.sh <service> <new-tag> <stage|prod>
```

## Scaling configuration

- **dev**: 1 replica + KEDA ScaledObject on `promotion-service` — scales to 0 when Kafka topic `promotion-events` has no lag, up to 3 when lag ≥ 10
- **staging**: HPA 2–4 replicas
- **prod**: HPA 2–8 replicas + `podAntiAffinity` to spread across nodes

## Istio (prod only)

Applied automatically by `Jenkinsfile-prod`. Apply manually after Istio is installed:

```bash
kubectl apply -f istio/peer-authentication.yml   # mTLS STRICT in prod, PERMISSIVE in stage
kubectl apply -f istio/destination-rules.yml     # circuit breakers + canary subsets
kubectl apply -f istio/virtual-services.yml      # canary 80/20 for promotion-service, retry policies
```

## Chaos Engineering

Requires Chaos Mesh installed (`enable_chaos = true` in Terraform):

```bash
kubectl apply -f chaos/pod-chaos.yml       # kills promotion-service pods every 2m
kubectl apply -f chaos/network-chaos.yml   # 500ms latency on auth→identity traffic
kubectl apply -f chaos/stress-chaos.yml    # CPU/memory stress on neo4j
```
