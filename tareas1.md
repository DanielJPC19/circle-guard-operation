# Tareas CircleGuard — IngeSoft V
**Deadline:** 12 junio 2026 | **Fecha de referencia:** 5 junio 2026

---

## TAREAS COMPLETADAS ✅

### [T-01] Crear `infra/envs/staging/` — Terraform Staging (AKS)
- [x] `infra/envs/staging/backend.tf` — Backend remoto Azure Blob Storage (`cgtfstate/tfstate`, key: `staging/terraform.tfstate`)
- [x] `infra/envs/staging/variables.tf` — Variables: `subscription_id`, `resource_group`, `location`, `acr_name`, `node_count`
- [x] `infra/envs/staging/terraform.tfvars` — Valores placeholder con instrucciones de uso (gitignored por `.gitignore`)
- [x] `infra/envs/staging/main.tf` — Provider `azurerm` + `helm`; llama módulos `acr`, `aks` (con `acr_id` desde `module.acr.acr_id`), `k8s_addons` (enable_istio, enable_chaos, enable_monitoring, enable_elk, enable_jaeger, enable_sealed_secrets = true)
- [x] `infra/modules/aks/outputs.tf` — Agregados outputs `kube_config_host`, `kube_config_client_certificate`, `kube_config_client_key`, `kube_config_cluster_ca_certificate` para que el Helm provider de staging pueda autenticarse al cluster

---

### [T-02] Crear `infra/envs/prod/` — Terraform Producción (GKE)
- [x] `infra/envs/prod/backend.tf` — Backend remoto GCS (`circleguard-tfstate`, prefix: `prod/terraform.tfstate`)
- [x] `infra/envs/prod/variables.tf` — Variables: `gcp_project`, `region`, `node_count`
- [x] `infra/envs/prod/terraform.tfvars` — Valores placeholder con instrucciones de `gcloud auth` (gitignored)
- [x] `infra/envs/prod/main.tf` — Provider `google` + data source `google_client_config` para token de acceso; provider `helm` apunta al endpoint del cluster GKE; llama módulos `gke` y `k8s_addons` (enable_istio, enable_monitoring, enable_elk, enable_jaeger, enable_finops, enable_sealed_secrets = true; enable_chaos = false en prod)

---

### [T-03] Prometheus scraping annotations en manifests de servicios
**Archivo:** `k8s/services/stage/all-services.yml`
- [x] `auth-service` → `prometheus.io/scrape: "true"`, `port: "8180"`, `path: "/actuator/prometheus"`
- [x] `identity-service` → `port: "8083"`
- [x] `promotion-service` → `port: "8088"`
- [x] `gateway-service` → `port: "8087"`
- [x] `notification-service` → `port: "8082"`
- [x] `form-service` → `port: "8086"`

**Archivo:** `k8s/services/prod/all-services.yml`
- [x] `auth-service` → `port: "8180"`
- [x] `identity-service` → `port: "8083"`
- [x] `promotion-service` → `port: "8088"`
- [x] `gateway-service` → `port: "8087"`
- [x] `notification-service` → `port: "8082"`
- [x] `form-service` → `port: "8086"`

> Nota: Las annotations se colocan en `template.metadata.annotations` (nivel pod), no en el deployment. Esto permite que el Prometheus operator con annotations autodiscovery raspe los pods automáticamente.

---

### [T-04] Crear `k8s/monitoring/prometheus-rules.yml` — AlertingRules
- [x] `PodCrashLooping` — más de 2 reinicios/min en namespace `circleguard-*` durante 2min → severity: critical
- [x] `DeploymentRolloutStuck` — réplicas unavailable durante 5min → severity: warning
- [x] `HighP99Latency` — P99 HTTP > 2 segundos durante 3min → severity: warning
- [x] `KafkaConsumerLagHigh` — consumer group lag > 1000 mensajes durante 5min → severity: warning
- [x] `Neo4jHeapHigh` — heap Neo4j > 85% durante 5min → severity: warning
- [x] Resource tipo `PrometheusRule` compatible con `kube-prometheus-stack` (label `release: kube-prometheus-stack`)

---

### [T-05] Crear `k8s/monitoring/grafana-dashboards-configmap.yml` — Dashboards as code
- [x] Dashboard **JVM Overview** — heap used, GC pause rate, live threads (por servicio, namespace circleguard-*)
- [x] Dashboard **HTTP Requests** — request rate, error rate 5xx, P99 latency (por servicio)
- [x] Dashboard **Kafka** — consumer group lag, producer send rate
- [x] ConfigMaps con label `grafana_dashboard: "1"` para auto-import vía Grafana sidecar (sin configuración manual)

---

### [T-06] Crear `k8s/monitoring/alertmanager-config.yml` — Alertmanager
- [x] Secret `alertmanager-kube-prometheus-stack-alertmanager` en namespace `monitoring`
- [x] Receptor `slack-notifications` — webhook Slack al canal `#circleguard-alerts`, con título y descripción del alert
- [x] Receptor `pagerduty-critical` — routing key PagerDuty para alertas críticas
- [x] Rutas: `severity=critical` → PagerDuty + Slack; `severity=warning` → solo Slack
- [x] Inhibición: critical suprime warnings del mismo alertname+namespace
- [x] Placeholders `REPLACE_WITH_SLACK_WEBHOOK_URL` y `REPLACE_WITH_PAGERDUTY_INTEGRATION_KEY`

---

### [T-07] Crear `k8s/logging/logstash-pipeline-configmap.yml` — ELK Pipeline
- [x] ConfigMap `logstash-pipeline` en namespace `logging`
- [x] Input: Filebeat en puerto 5044
- [x] Filter: `json { source => "message" }` para parsear logs JSON de Spring Boot; extrae `service_name`, `trace_id`, `span_id`, `log_level`, `thread` desde la estructura de log
- [x] Filter: extrae `environment` y `service` desde metadata de Kubernetes (namespace, labels.app)
- [x] Output: Elasticsearch con índice dinámico `circleguard-{service}-{YYYY.MM.dd}`

---

### [T-08] Crear `k8s/logging/filebeat-daemonset.yml` — Recolección de logs
- [x] ConfigMap `filebeat-config` — autodiscover por Kubernetes con hints habilitados; filtra por namespace `circleguard-*`; output a `logstash:5044`
- [x] DaemonSet `filebeat` — imagen `docker.elastic.co/beats/filebeat:8.5.0`; monta `/var/log/containers`, `/var/log/pods`, `/var/lib/docker/containers` como HostPath; variable `NODE_NAME` desde fieldRef
- [x] ServiceAccount `filebeat` con ClusterRole que permite `get/list/watch` sobre namespaces, pods y nodes
- [x] ClusterRoleBinding para el ServiceAccount

---

### [T-10] Crear `docs/design-patterns.md` — Documentación de patrones
- [x] **Repository Pattern** — interfaces `*Repository` en todos los servicios; abstrae acceso a PostgreSQL y Neo4j
- [x] **Factory Pattern** — `DualChainAuthenticationProvider` en auth-service; crea el proveedor de autenticación correcto (LDAP vs DB)
- [x] **Observer Pattern** — `SurveyListener` en promotion-service consume eventos Kafka; desacopla form-service de promotion-service
- [x] **Decorator Pattern** — `JwtAuthenticationFilter` en gateway-service; envuelve la cadena Spring Security
- [x] **Circuit Breaker** (infraestructura) — `DestinationRule` Istio con `outlierDetection`; 5 errores consecutivos → expulsión del pool 30s; extracto YAML incluido
- [x] **External Configuration** (infraestructura) — ConfigMap + SealedSecrets + Spring Profiles; flujo completo documentado
- [x] **Saga Choreography** (infraestructura) — cascada form-service → Kafka → promotion-service → Kafka → notification-service; compensación por reintento automático Kafka
- [x] Tabla de beneficios combinados (resiliencia, mantenibilidad, escalabilidad)

---

### [T-11] Integrar Chaos Mesh en `Jenkinsfile-staging`
- [x] Nuevo parámetro `booleanParam(name: 'RUN_CHAOS', defaultValue: false)` en la sección `parameters`
- [x] Nuevo stage **"Chaos Experiments"** con bloque `when { expression { return params.RUN_CHAOS } }`
- [x] Aplica los 3 manifests de `chaos/`, espera 5 minutos (`sleep 300`), muestra pods en vivo, hace `kubectl delete` al finalizar
- [x] El stage es **opt-in** — no bloquea deploys normales si no se activa

---

### [T-12] Crear `docs/chaos-results.md` — Resultados Chaos Engineering
- [x] **Experimento 1 (PodChaos)** — pod-kill en promotion-service cada 2min; esperado: ReplicaSet recrea en <30s, readiness probe (90s) previene tráfico anticipado, Istio retry absorbe requests en vuelo
- [x] **Experimento 2 (NetworkChaos)** — 500ms latency en auth→identity; esperado: Istio retry policy (3 intentos × 2s) mantiene error rate <5%, circuit breaker actúa si persiste
- [x] **Experimento 3 (StressChaos)** — CPU stress 90% en neo4j; esperado: HPA de promotion-service escala de 2→4 réplicas, alerta `Neo4jHeapHigh` se dispara
- [x] Lecciones aprendidas por experimento
- [x] Fragmento Groovy del stage de Jenkins

---

### [T-13] Crear `docs/cost-analysis.md` — FinOps
- [x] Tabla de costos estimados: DO $48/mes, AKS $140/mes, GKE $230/mes, ACR $20/mes → Total ~$438/mes
- [x] **Estrategia 1: KEDA scale-to-zero** — ScaledObject de promotion-service en dev; cálculo de ahorro ~$20/mes
- [x] **Estrategia 2: Nodo mínimo 1** — autoscaling dev baja a 1 nodo fuera de horario; ahorro ~$12/mes
- [x] **Estrategia 3: Committed Use Discounts GKE** — 1-year CUD en e2-standard-4; ahorro ~$59/mes (20%)
- [x] **Estrategia 4: Right-sizing** — notification-service y form-service de 512Mi→384Mi RAM request; ahorro ~15%
- [x] Instrucciones `kubectl port-forward` para acceder a Kubecost
- [x] Proyección: costo optimizado ~$317/mes (ahorro ~27%)

---

### [T-14] Crear `docs/multi-cloud-comparison.md` — Comparativa Multi-Cloud
- [x] Tabla de arquitectura 3 clouds con razón de elección para cada uno
- [x] Tabla de métodos de autenticación ACR por cloud (MSI en AKS, imagePullSecrets en DOKS y GKE)
- [x] Tabla comparativa técnica: costo/hora, tiempo provisión, SLA, autoscaling, Workload Identity, Network Policy, Istio, deletion protection
- [x] Estrategia DNS: `api.circleguard.edu` → GKE prod, `api-stage.circleguard.edu` → AKS staging
- [x] Backup strategy: DO Spaces / Azure Blob / GCS por ambiente; ACR geo-replication opcional; Git como fuente de verdad
- [x] 5 lecciones aprendidas documentadas

---

### [T-15] Crear `docs/operations-manual.md` — Manual de Operaciones
- [x] Sección de prerrequisitos (kubectl, terraform, kubeseal, helm, gcloud, az, doctl)
- [x] **Runbook: Deploy manual completo** — 7 pasos en orden con comandos exactos
- [x] **Runbook: Regenerar Sealed Secrets** — uso de `setup-sealed-secrets.sh` con regeneración y apply
- [x] **Runbook: Rollback de un servicio** — `rollout history`, `rollout undo`, con y sin `--to-revision`
- [x] **Runbook: Escalar manualmente** — `kubectl scale` y cómo ver el HPA
- [x] **Runbook: Ejecutar Chaos Experiments** — apply/delete con monitoreo en vivo
- [x] **Acceso a dashboards** — port-forward para Grafana (3000), Kibana (5601), Jaeger (16686), Kiali (20001), Kubecost (9090) con credenciales
- [x] **Troubleshooting: CrashLoopBackOff** — logs, describe, causas comunes
- [x] **Troubleshooting: OOMKilled** — `kubectl top pods`, solución con MaxRAMPercentage
- [x] **Troubleshooting: Kafka Consumer Lag alto** — consulta desde dentro del pod, causa KEDA scale-to-zero
- [x] **Troubleshooting: Istio mTLS rechazado** — verificar PeerAuthentication, label istio-injection, rollout restart
- [x] **Troubleshooting: cert-manager sin certificado** — `describe certificate`, ver challenges, verificar DNS

---

### [T-16] Crear `.github/workflows/ci-develop.yml` — CI para rama develop
- [x] Trigger: `push` a `develop` y `pull_request` hacia `develop`
- [x] Steps: Checkout → JDK 21 (temurin) → Cache Gradle → `./gradlew build -x test` → Unit tests + JaCoCo → SonarQube analysis → SonarQube Quality Gate (bloquea si falla) → Login ACR → `docker build` + `docker push` `:dev-{SHORT_SHA}` para los 6 servicios → Trivy scan (bloquea en CRITICAL/HIGH) → Upload SARIF a GitHub Security tab
- [x] Notificación Slack con URL del build si el job falla
- [x] Labels en imagen: `git.sha`, `git.branch`

---

### [T-17] Crear `.github/workflows/ci-release.yml` — CI para ramas release/*
- [x] Trigger: `push` a `release/**`
- [x] Steps: build → unit tests → **integration tests con Testcontainers** → SonarQube + Quality Gate → Login ACR → push `:staging-{SHORT_SHA}` → Trivy scan → **Trigger Jenkins Staging** vía HTTP POST (verifica HTTP 201) → **Espera resultado Jenkins** (poll hasta 30min, falla si result != SUCCESS) → **E2E tests** con port-forward a AKS staging
- [x] Output `image_tag` exportado para referencia entre steps

---

### [T-18] Crear `.github/workflows/ci-main.yml` — CI/CD para rama main (Producción)
- [x] Trigger: `push` a `main`
- [x] Job `build-and-test`: build → unit + integration tests → SonarQube → Login ACR → push `:prod-{SHA}` + `:latest` → Trivy → **OWASP ZAP Full Scan** contra `https://api-stage.circleguard.edu` (usa `.zap/rules.tsv`) → **Locust** 50 usuarios 5min (umbral: <5% error) → Upload artefactos (JaCoCo reports, CSV de Locust)
- [x] Job `deploy-production`: depende de `build-and-test`; usa **GitHub Environment `production`** (requiere aprobación manual) → Trigger Jenkins Prod → Espera resultado Jenkins

---

### [T-19] Versionado semántico automático en `ci-main.yml`
- [x] Lee el último git tag con `git describe --tags --abbrev=0`
- [x] Parsea `MAJOR.MINOR.PATCH` desde el tag anterior
- [x] Detecta `BREAKING CHANGE` / `feat!:` → bump MAJOR; `feat:` → bump MINOR; resto → bump PATCH
- [x] Crea el tag `vMAJOR.MINOR.PATCH` y lo pushea al repositorio
- [x] Crea **GitHub Release** automático con `generate_release_notes: true` y adjunta CSV de Locust

---

### [T-21] Crear `.zap/rules.tsv` — OWASP ZAP falsos positivos
- [x] Regla `10096` (Timestamp Disclosure) → IGNORE
- [x] Regla `10015` (Incomplete Cache-control Header) → IGNORE
- [x] Regla `10020` (X-Frame-Options) → IGNORE
- [x] Regla `10027` (Suspicious Comments) → IGNORE

---

### [T-22] Crear `docs/architecture.md` — Diagramas Mermaid
- [x] **Diagrama multi-cloud general** — Developer → GitHub Actions → ACR → DOKS/AKS/GKE; sub-grafos por ambiente con sus componentes
- [x] **Diagrama de flujo CI/CD completo** (SequenceDiagram) — develop → release/* → main; muestra cada step, condición de rollback, aprobación manual y git tag
- [x] **Diagrama de red Kubernetes** — Internet → Ingress → gateway-service → 5 microservicios → middleware (postgres, neo4j, kafka, redis, ldap); NetworkPolicy documentada
- [x] **Diagrama de observabilidad** — Spring Boot Actuator → Prometheus → Grafana + Alertmanager → Slack/PagerDuty; Filebeat → Logstash → Elasticsearch → Kibana; Spring Sleuth → Jaeger

---

### [T-23] Crear `docs/change-management.md` — Change Management
- [x] Diagrama de flujo de promoción: feature → develop → release/* → main con criterios de cada paso
- [x] Tabla de criterios de aprobación para producción (6 checks con herramienta y umbral)
- [x] Comandos de rollback automático (Jenkins) y rollback manual (`rollout history/undo`)
- [x] Tabla de versionado semántico por tipo de commit con ejemplos
- [x] Script completo de versionado semántico (bash)
- [x] Formato de Release Notes automáticas con secciones feat/fix/chore

---

### [T-24] Actualizar `README.md`
- [x] Tabla de documentación con links a los 7 archivos en `docs/`
- [x] Sección **GitHub Actions Secrets requeridos** con tabla de 11 secrets (ACR, SonarQube, Jenkins, GH_TOKEN, Slack, Azure Subscription)

---

### [T-Aux] CLAUDE.md — Guía del repositorio
- [x] Archivo `CLAUDE.md` con arquitectura multi-cloud, comandos Terraform por ambiente, orden de deploy K8s, workflow Sealed Secrets, descripción de Jenkins pipelines, convención de image tags, configuración de scaling, Istio y Chaos Engineering

---

## TAREAS PENDIENTES ⏳

### Alta Prioridad 🔴

- [ ] **[P-01] Sealed Secrets reales** — Ejecutar `./scripts/setup-sealed-secrets.sh dev|staging|prod` con las credenciales verdaderas para reemplazar los placeholders `REPLACE_WITH_KUBESEAL_OUTPUT` en `k8s/secrets/sealed-secret-{dev,stage,prod}.yml`
  - Requiere: cluster activo + `kubeseal` CLI instalado y apuntando al cluster correcto
  - Secretos necesarios: `POSTGRES_PASSWORD`, `NEO4J_PASSWORD`, `JWT_SECRET`, `QR_SECRET`, `VAULT_SECRET`, `VAULT_SALT`, `VAULT_HASH_SALT`, `LDAP_MANAGER_PASSWORD`

- [ ] **[P-02] Valores reales en terraform.tfvars** — Reemplazar placeholders en cada env:
  - `infra/envs/dev/terraform.tfvars` → `do_token = "REPLACE_WITH_DO_TOKEN"`
  - `infra/envs/staging/terraform.tfvars` → `subscription_id = "REPLACE_WITH_AZURE_SUBSCRIPTION_ID"`
  - `infra/envs/prod/terraform.tfvars` → `gcp_project = "REPLACE_WITH_GCP_PROJECT_ID"`

- [ ] **[P-03] GitHub Actions Secrets** — Configurar en GitHub → Settings → Secrets → Actions los 11 secrets listados en el `README.md`:
  - `ACR_LOGIN_SERVER`, `ACR_USERNAME`, `ACR_PASSWORD`
  - `SONARQUBE_URL`, `SONARQUBE_TOKEN`
  - `JENKINS_STAGING_URL`, `JENKINS_PROD_URL`, `JENKINS_TOKEN`
  - `GH_TOKEN`, `SLACK_WEBHOOK`, `AZ_SUBSCRIPTION_ID`

- [ ] **[P-04] GitHub Environment `production`** — Crear el Environment en GitHub → Settings → Environments → `production` con revisores requeridos para la aprobación manual del deploy a GKE

---

### Media Prioridad 🟠

- [ ] **[P-05] Prometheus annotations en servicios dev** — Agregar `prometheus.io/scrape`, `prometheus.io/port`, `prometheus.io/path` a los 6 archivos individuales en `k8s/services/dev/`:
  - `auth-service.yml` → port 8180
  - `identity-service.yml` → port 8083
  - `promotion-service.yml` → port 8088
  - `gateway-service.yml` → port 8087
  - `notification-service.yml` → port 8082
  - `form-service.yml` → port 8086

- [ ] **[P-06] Locust performance test** — Crear `tests/performance/locustfile.py` en el repo `circleguard-app` (NO en este repo):
  - Flujo: login → `/api/v1/health-status/me` (peso 3) → `/api/v1/questionnaires` (peso 1)
  - Umbral: < 5% error rate con 50 usuarios durante 5 minutos

- [ ] **[P-07] Alertmanager — valores reales** — Reemplazar en `k8s/monitoring/alertmanager-config.yml`:
  - `REPLACE_WITH_SLACK_WEBHOOK_URL` → URL real del Slack Incoming Webhook
  - `REPLACE_WITH_PAGERDUTY_INTEGRATION_KEY` → Integration key de PagerDuty

---

### Baja Prioridad / Externos 🟡

- [ ] **[P-08] GitHub Projects — evidencia de sprints** — Crear board en GitHub Projects con:
  - Sprint 1 (25 mayo – 2 junio) con issues cerrados
  - Sprint 2 (3 – 10 junio) con issues en progreso
  - User stories con criterios de aceptación en cada issue

- [ ] **[P-09] Jaeger sidecar annotation en deployments** — Agregar `sidecar.jaegertracing.io/inject: "true"` en `template.metadata.annotations` de los 6 servicios en stage y prod (requiere Jaeger operator instalado vía k8s-addons)

- [ ] **[P-10] Video demo** (10-15 min) con el siguiente flujo:
  1. Mostrar repos y branching strategy (GitFlow)
  2. Demo CI: push → GitHub Actions → SonarQube → Trivy → Docker push a ACR
  3. Demo CD: Jenkins staging deploy → auto-rollback demo
  4. Demo Istio: Kiali (topology), canary 80/20 en promotion-service, mTLS activo
  5. Demo Observabilidad: Grafana (JVM + HTTP dashboards), Kibana (logs), Jaeger (tracing)
  6. Demo Chaos: ejecutar experimento pod-kill en vivo, mostrar recuperación en Grafana
  7. Demo FinOps: Kubecost dashboard con costos por namespace
  8. Demo Multi-cloud: mostrar los 3 clusters activos con `kubectl get nodes`

- [ ] **[P-11] Presentación final** (20-30 min para el profesor):
  - Diapositivas con diagramas de `docs/architecture.md`
  - Demo en vivo de los puntos anteriores
  - Sección de lecciones aprendidas y recomendaciones

- [ ] **[P-12] Verificación final pre-entrega**
  - [ ] `terraform validate` en `infra/envs/dev`, `infra/envs/staging`, `infra/envs/prod`
  - [ ] `kubectl apply --dry-run=client -f k8s/` en todos los manifests
  - [ ] `grep -r "REPLACE_" .` para confirmar que no quedan placeholders reales
  - [ ] Confirmar que no hay secrets en texto plano versionados en git

---

## Resumen de Cobertura por Rubro

| Rubro | Peso | Estado | Notas |
|---|---|---|---|
| Terraform IaC | 20% | ✅ Completo | Módulos + 3 envs (dev/staging/prod) con backends remotos |
| CI/CD Avanzado | 15% | ✅ Completo | 3 workflows GHA + 2 Jenkinsfiles + SonarQube + Trivy + Semantic versioning |
| Pruebas Completas | 15% | 🟡 ~80% | Unit/Integration/E2E/ZAP definidos; Locust pendiente en app repo |
| Metodología Ágil | 10% | 🟠 ~50% | GitFlow implementado; GitHub Projects pendiente [P-08] |
| Patrones de Diseño | 10% | ✅ Completo | 7 patrones documentados en `docs/design-patterns.md` |
| Observabilidad | 10% | ✅ Completo | Prometheus + Grafana + Alertmanager + ELK + Jaeger (como código) |
| Documentación | 10% | 🟡 ~80% | 7 docs + README + CLAUDE.md; video pendiente [P-10] |
| Change Management | 5% | ✅ Completo | Proceso formal + Release Notes + Rollback plan documentados |
| Seguridad | 5% | ✅ Completo | Trivy + Sealed Secrets + RBAC + TLS + OWASP ZAP |
| **Bonus Multi-cloud** | 5% | ✅ Completo | 3 clouds + ACR central + comparativa documentada |
| **Bonus Istio** | 5% | ✅ Completo | mTLS STRICT + canary 80/20 + circuit breakers + retry policies |
| **Bonus Chaos** | 5% | ✅ Completo | 3 experimentos + integrado en pipeline + resultados documentados |
| **Bonus FinOps** | 5% | ✅ Completo | Kubecost + KEDA + análisis de costos documentado |
