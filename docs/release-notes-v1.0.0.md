# CircleGuard — Release Notes v1.0.0

**Fecha de release:** 2026-06-12 (planificada)
**Versión:** 1.0.0 (primera versión estable)
**Repositorios:**
- `circle-guard-development` (DEV) — código de los 8 microservicios (auth, identity, promotion, notification, form, gateway, dashboard, file)
- `circle-guard-operation` (OPS) — infraestructura (Terraform multi-cloud), CI/CD (GitHub Actions + Jenkins), Kubernetes manifests, y documentación técnica

> **Ubicación sugerida:** `circle-guard-operation/docs/release-notes-v1.0.0.md`
> (recomendado mirror en `circle-guard-development/docs/` para que ambos repos lo referencien).

---

## Resumen de la versión

`v1.0.0` es la primera versión estable de **CircleGuard**, una plataforma de
microservicios para monitoreo de salud en un campus universitario. Esta versión
entrega la plataforma completa de 8 microservicios desplegable sobre Kubernetes
multi-cloud, con prácticas de DevOps de extremo a extremo: infraestructura como
código, CI/CD con promoción controlada por ambientes, suite de pruebas
(unitarias, integración, E2E, rendimiento, seguridad), observabilidad,
seguridad y service mesh.

---

## Componentes principales

La plataforma se compone de 8 microservicios Spring Boot (Java/Kotlin, Gradle):

| Servicio | Responsabilidad |
|----------|-----------------|
| `auth-service` | Autenticación y emisión de tokens. |
| `identity-service` | Gestión de identidad de usuarios. |
| `promotion-service` | Lógica de promoción/campañas de salud. |
| `notification-service` | Notificaciones (consumo de eventos Kafka). |
| `form-service` | Formularios de salud. |
| `gateway-service` | API Gateway / enrutamiento. |
| `dashboard-service` | Agregación para tableros. |
| `file-service` | Carga y descarga de archivos. |

---

## Novedades por capacidad

### Infraestructura como código (Terraform) ✅
- **Módulos reutilizables** en `infra/modules/`: AKS (Azure Kubernetes Service), ACR (Azure Container Registry), k8s-addons (Helm charts para cert-manager, Prometheus, Grafana, sealed-secrets, etc.).
- **Multi-cloud:** DigitalOcean (DOKS — dev), Azure (AKS — staging), Google Cloud (GKE — prod).
- **Ambientes separados** en `infra/envs/dev`, `infra/envs/staging`, `infra/envs/prod`, más `infra/envs/shared` para recursos globales.
- **Backend remoto configurado por ambiente:** Azure Blob Storage (`cgtfstate` storage account, `tfstate` container, claves separadas por env).
- **Validación:** `terraform validate` pasa en los 3 ambientes (sin errores de sintaxis).

### CI/CD ✅
- **GitHub Actions pipelines** en `circle-guard-development/.github/workflows/`:
  - `ci-develop.yml`: Build + unit tests + SonarQube + Trivy → push `:dev-{SHA}` a ACR.
  - `ci-release.yml`: + integration tests + SonarQube quality gate → push `:staging-{SHA}` → trigger Jenkinsfile-staging.
  - `ci-main.yml`: + OWASP ZAP (DAST) + Locust (performance) + SonarQube quality gate → push `:prod-{SHA}` → aprobación manual → trigger Jenkinsfile-prod.
- **Jenkins CD pipelines** en `circle-guard-operation/`:
  - `Jenkinsfile-staging`: Deploy a AKS staging, reset DB, health checks (50+ retries × 15s).
  - `Jenkinsfile-prod`: Deploy a AKS prod, Istio manifests, release notes generadas, auto-rollback en timeout.
- **Promoción controlada:** dev (automatic) → staging (Jenkins gate) → prod (manual approval + Jenkins).
- **Notificaciones:** Slack en fallos de pipeline y rollbacks.

### Pruebas y calidad ✅
- **Unitarias (JUnit):** Todos los 8 servicios con pruebas de controladores, servicios, repositorios. Build task `unitTest` excluye integración.
- **Integración (Testcontainers + @EmbeddedKafka):**
  - `auth-service`: AuthIntegrationTest, AuthLdapIntegrationTest (PostgreSQL).
  - `form-service`: SurveyIntegrationTest (Testcontainers).
  - `promotion-service`: PromotionIntegrationTest, UserNodeRepositoryIntegrationTest (PostgreSQL + Neo4j).
  - `dashboard-service`: Integration tests con Testcontainers.
  - `notification-service`: Listeners y servicios con @EmbeddedKafka.
  - `file-service`: FileUploadControllerTest (integración).
- **E2E (REST Assured):** Flujos completos en `tests/e2e/` contra servicios desplegados (gateway-service como punto de entrada).
- **Performance & Stress (Locust):** `tests/performance/locustfile.py` con 50 usuarios simultáneos, 5 min de duración, threshold 5% error rate. Ejecutable con `locust -f locustfile.py --host=http://localhost:8087`.
- **Cobertura (JaCoCo):** Mínimo 70% de line coverage aplicado como verificación (`jacocoTestCoverageVerification`). Reports en `build/reports/jacoco/`.
- **Análisis estático (SonarQube):** Proyector key: `circleguard`, URL configurable en CI. Quality gate integrado en pipelines.

### Observabilidad y monitoreo ✅
- **Prometheus:** Scraping de métricas Micrometer de todos los servicios (via `spring-boot-starter-actuator`). Reglas de alerta en `k8s/monitoring/prometheus-rules.yml` (PodCrashLooping, HighP99Latency, etc.).
- **Grafana:** Dashboards configmaps en `k8s/monitoring/grafana-dashboards-configmap.yml` con vistas por servicio, latencias, disponibilidad.
- **Alertmanager:** Gestión centralizada de alertas (`k8s/monitoring/alertmanager-config.yml`), enrutamiento a Slack/email.
- **Stack ELK (Elasticsearch, Logstash, Kibana):**
  - **Filebeat (DaemonSet):** Colecta logs de pods (`k8s/monitoring/filebeat-daemonset.yml`, `k8s/logging/filebeat-daemonset.yml`).
  - **Logstash:** Procesamiento y normalización (`k8s/monitoring/logstash-configmap.yml`, `k8s/logging/logstash-pipeline-configmap.yml`).
  - **Kibana:** Visualización (deployments en cada ambiente, index pattern `circleguard-*`).
- **Health checks (Kubernetes):**
  - Liveness probes: detectan pods en loop infinito.
  - Readiness probes: tráfico enrutado solo a pods listos.
  - Endpoint: `http://{service}:8087/actuator/health` (gateway como punto de entrada).
  - Timeout: 24 reintentos × 15 segundos después de warmup de 90 segundos (Jenkinsfile).

### Seguridad ✅
- **Escaneo de vulnerabilidades:**
  - **Trivy:** Escaneo de imágenes Docker en CI (`.github/workflows/ci-*.yml`), salida SARIF integrada.
  - **SonarQube:** Análisis estático de código Java/Kotlin detectando code smells y vulnerabilidades (Quality Gate bloqueante en CI).
  - **OWASP ZAP:** Escaneo DAST en `ci-main.yml` contra endpoints de producción.
- **Gestión de secretos:**
  - **Sealed Secrets (Bitnami):** Cifrado en reposo. Archivos `k8s/secrets/sealed-secret-{env}.yml` contienen SealedSecret (seguros para git).
  - Script de regeneración: `scripts/setup-sealed-secrets.sh` (solicita valores al operador, genera YAML cifrado).
  - Secretos manejados: `POSTGRES_PASSWORD`, `NEO4J_PASSWORD`, `JWT_SECRET`, `QR_SECRET`, `VAULT_*`, `LDAP_MANAGER_PASSWORD`.
- **RBAC (Role-Based Access Control):**
  - Por namespace (circlegard-dev, circleguard-stage, circleguard-prod).
  - `k8s/namespaces/circleguard-*.yml` definen Role (developer-role: get/list/watch sobre pods, services, deployments) y RoleBinding.
  - ServiceAccount circleguard-sa por namespace.
- **TLS/mTLS:**
  - **TLS externamente:** cert-manager con ClusterIssuer `letsencrypt-prod` (Let's Encrypt). Ingress en `k8s/services/{env}/ingress.yml` con secretName `circleguard-tls-{env}`.
  - **mTLS internamente (Istio):** PeerAuthentication STRICT en prod (`istio/peer-authentication.yml`), PERMISSIVE en staging.
- **NetworkPolicy:**
  - Definidas en namespaces (`k8s/namespaces/circleguard-*.yml`).
  - Ingress: tráfico solo desde el mismo namespace + istio-system.
  - Egress: mismo namespace + DNS (53) + HTTPS (443) hacia sistemas externos.

### Service Mesh, resiliencia y optimización (bonificaciones) ✅
- **Istio (5% bonus):**
  - **DestinationRules** (`istio/destination-rules.yml`): Circuit Breaker con outlier detection (5 errores 5xx consecutivos, ejection 30s, máximo 50% de instancias aisladas). Límites de conexión por servicio.
  - **VirtualServices** (`istio/virtual-services.yml`): Canary deployments (80/20 split para promotion-service), políticas de reintento.
  - **PeerAuthentication** (`istio/peer-authentication.yml`): mTLS STRICT en prod, PERMISSIVE en staging.
  - **Instalación:** Helm charts vía `k8s-addons` Terraform module, aplicado en Jenkinsfile (`kubectl apply -f istio/`).
- **Chaos Engineering (5% bonus):**
  - **Chaos Mesh** deployments (`chaos/pod-chaos.yml`, `chaos/network-chaos.yml`, `chaos/stress-chaos.yml`).
  - Pod Chaos: mata promotion-service pods cada 2 minutos.
  - Network Chaos: inyecta 500ms latencia en tráfico auth→identity.
  - Stress Chaos: carga CPU/memoria en Neo4j.
  - Ejecución: stage dedicado en Jenkinsfile-staging (opcional con flag `RUN_CHAOS=true`).
  - Documentación de resultados: `docs/chaos-results.md`.
- **FinOps (5% bonus):**
  - **KEDA (Kubernetes Event Autoscaling):** Scale-to-zero para promotion-service basado en Kafka topic lag. ScaledObject en `k8s/services/*/` con escalado 0→3 según `promotion-events` lag threshold.
  - **Kubecost + analysis:** Cost por proveedor, nodo, servicio. Datos exportados en `docs/cost-analysis.md` (DOKS ~$48/mes, AKS ~$140/mes, GKE ~$230/mes, total ~$438/mes).
  - **Dashboards Grafana FinOps:** Métrica de coste actual vs presupuestado.

---

## Limitaciones conocidas

### Tracing distribuido (OpenTelemetry/Jaeger) — **PENDIENTE** ⚠️
- **Estado:** La infraestructura para Jaeger está lista en la stack de observabilidad, pero los **microservicios no incluyen las dependencias de OpenTelemetry/Micrometer Tracing**.
- **Qué falta:**
  - Agregar `io.micrometer:micrometer-tracing-bridge-otel` y `io.opentelemetry.exporter:opentelemetry-exporter-jaeger-thrift` a `build.gradle.kts`.
  - Configurar propiedades Spring: `management.tracing.sampling.probability=1.0`, endpoints de Jaeger.
  - Injector de traces en todas las clases de servicio.
- **Impacto:** Trazado de extremo a extremo no operativo. Prometheus/Grafana siguen funcionando para métricas de negocio.
- **Planificado para:** `v1.1.0` (HU-22 en Sprint 3).

### Validación E2E en clúster vivo — **PARCIAL**
- Algunos flujos de verificación (health checks contra clúster, pruebas E2E de integración multi-servicio) requieren **clústeres activos con credenciales reales**.
- Pruebas unitarias e integración local (Testcontainers) funcionan sin infraestructura viva.
- Tests E2E contra clúster desplegado requieren acceso a Azure/GCP y credenciales de service principal.

### GitHub Projects board — **NO IMPLEMENTADO**
- Las HU se rastrean en mensajes de commit (`git log --grep="US-"`), no en un board formal.
- Planificado para futuras iteraciones (HU-27).

---

## Documentación incluida en v1.0.0

Los siguientes documentos están disponibles en `circle-guard-operation/docs/`:

- **`architecture.md`:** Visión general, componentes, 3 diagramas mermaid (AKS, CI/CD, microservicios).
- **`design-patterns.md`:** 7 patrones implementados (Repository, Factory, Observer, Decorator, Circuit Breaker, External Config, Saga Choreography) con ejemplos de código.
- **`operations-manual.md`:** Guía paso a paso para deploy en dev/staging/prod, troubleshooting, rollback, escalado.
- **`change-management.md`:** Convención de commits, checklist de aprobación, versionado semántico, impacto en release.
- **`cost-analysis.md`:** Desglose de costos por proveedor, estrategia FinOps, proyecciones.
- **`multi-cloud-comparison.md`:** Análisis de trade-offs entre DOKS, AKS, GKE.
- **`chaos-results.md`:** Resultados de experimentos de Chaos Mesh (resiliencia validada).
- **`agile-methodology.md`:** Metodología Scrum, estrategia de branching, sprint history, épicas (este documento corresponde a US-25).
- **`release-notes-v1.0.0.md`:** Este documento (US-26 + US-33).
- **`README.md` (OPS):** Visión general del repo, requisitos de CLI, comandos Terraform/kubectl, workflow Sealed Secrets.
- **`README.md` (DEV):** Estructura de microservicios, ejecución local, comandos de test, pipeline CI/CD.

---

## Plan de rollback

En caso de que un despliegue de `v1.0.0` presente fallas en producción:

1. **Detener la promoción.** El despliegue a producción requiere aprobación
   manual; ante señales de falla durante la verificación, no aprobar/abortar el
   stage de despliegue en Jenkins.
2. **Revertir la imagen.** Re-desplegar la imagen de contenedor de la versión
   estable anterior actualizando el tag de imagen en los manifests
   (`scripts/update-image-tag.sh`) y aplicando los manifests previos.
3. **Revertir manifests de K8s.** `kubectl rollout undo deployment/<servicio> -n <namespace>`
   para volver al ReplicaSet anterior de cada servicio afectado.
4. **Revertir infraestructura (si aplica).** Si el cambio incluyó infraestructura,
   revertir al commit anterior en OPS y re-aplicar Terraform del ambiente.
5. **Verificar salud.** Confirmar liveness/readiness y métricas en Grafana antes
   de dar por estabilizado el rollback.
6. **Registrar el incidente** siguiendo el proceso de `docs/change-management.md`.

---

## Notas de actualización

Esta es la **primera versión estable** de CircleGuard (`v1.0.0`). No existen versiones previas en producción, por lo que no hay *breaking changes* ni rutas de migración.

**Historial esperado de versiones futuras:**
- **v1.0.0** (actual) — Entrega base (100% requerimientos + bonificaciones Istio, Chaos, FinOps).
- **v1.1.0** — OpenTelemetry/Jaeger completamente integrado, GitHub Projects board, video demo, slides.
- **v2.0.0** — (Futuro) Posibles cambios en event schema de Kafka o estructura de servicios.

---

## Versionado

CircleGuard sigue **Versionado Semántico (SemVer)** derivado de Conventional
Commits: `feat:` → versión menor, `fix:` → parche, `BREAKING CHANGE:` → versión
mayor. Esta versión corresponde al tag `v1.0.0`.

---

---

**Metadata:**
- Documento: Release Notes v1.0.0
- Historias de usuario: **US-26** (Release Notes), **US-33** (Release v1.0.0 tagging)
- Sección de rúbrica: 6 — Change Management + Release Notes (5%)
- Autor/es: Equipo CircleGuard
- Última actualización: 2026-06-11
- Estado: ✅ Listo para v1.0.0 (requiere git tag v1.0.0 en main)
