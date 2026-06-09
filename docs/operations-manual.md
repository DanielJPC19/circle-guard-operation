# Manual de Operaciones — CircleGuard

Guía práctica para operadores y SREs para administrar, monitorear y resolver problemas en CircleGuard.

---

## Requisitos Previos

Antes de comenzar, asegúrate de tener instalados:

```bash
# CLI Tools
kubectl 1.29+
terraform 1.7+
kubeseal          # Sealed Secrets CLI
az                # Azure CLI
helm 3.14+
jq                # JSON parser

# Acceso
- Service Principal Azure (appId + clientSecret)
- az login / az account set --subscription 7f77aa02-ccb3-4837-9e54-34f7d34af2b3
- Acceso a Jenkins
- Kubeconfig para los 3 clusters (todos AKS en Brazil South)
```

---

## 1. Deployments por Ambiente

### 1.1 Deploy a Development (AKS)

**Paso 1: Provisionar infraestructura**

```bash
az login
az account set --subscription 7f77aa02-ccb3-4837-9e54-34f7d34af2b3

cd infra/envs/dev
terraform init
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

**Paso 2: Obtener kubeconfig**

```bash
az aks get-credentials \
  --resource-group circleguard-dev-rg \
  --name circleguard-dev \
  --overwrite-existing
```

**Paso 3: Deploy manual de manifests**

```bash
# Crear namespace
kubectl apply -f k8s/namespaces/circleguard-dev.yml

# Aplicar cert-manager (una sola vez por cluster)
kubectl apply -f k8s/cert-manager/clusterissuer.yml

# Deploy middleware (Postgres, Neo4j, Kafka, Redis, OpenLDAP)
kubectl apply -f k8s/infra/ -n circleguard-dev

# Esperar que middleware esté listo
kubectl wait --for=condition=ready pod -l app=postgres \
  -n circleguard-dev --timeout=180s

# Aplicar ConfigMaps
kubectl apply -f k8s/configmaps/configmap-infra.yml

# Aplicar Sealed Secrets
kubectl apply -f k8s/secrets/sealed-secret-dev.yml

# Deploy servicios de aplicación
kubectl apply -f k8s/services/dev/ -n circleguard-dev

# Verificar rollout
kubectl rollout status deployment/gateway-service -n circleguard-dev
```

---

### 1.2 Deploy a Staging (AKS)

**Paso 1: Provisionar infraestructura**

```bash
# Autenticar en Azure
az login
az account set --subscription <SUBSCRIPTION_ID>

cd infra/envs/staging
terraform init
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

**Paso 2: Obtener kubeconfig**

```bash
az aks get-credentials \
  --resource-group circleguard-stage-rg \
  --name circleguard-aks-stage \
  --overwrite-existing
```

**Paso 3: Deploy automático con Jenkins**

```bash
# En Jenkins:
1. Ir a: Jenkinsfile-staging
2. Click: "Build with Parameters"
3. Ingresar: IMAGE_TAG = staging-<SHA>
4. Click: "Build"

# El pipeline ejecutará automáticamente:
# - GCloud auth & kubectl config
# - Create namespace
# - Deploy infrastructure
# - Apply ConfigMaps
# - Apply Sealed Secrets
# - Deploy servicios
# - Verify rollout
# - Optional: Run Chaos Experiments
```

---

### 1.3 Deploy a Production (AKS)

**Paso 1: Provisionar infraestructura**

```bash
az login
az account set --subscription 7f77aa02-ccb3-4837-9e54-34f7d34af2b3

cd infra/envs/prod
terraform init
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

**Paso 2: Obtener kubeconfig**

```bash
az aks get-credentials \
  --resource-group circleguard-prod-rg \
  --name circleguard-prod \
  --overwrite-existing
```

**Paso 3: Deploy automático con Jenkins (requiere aprobación)**

```bash
# En Jenkins:
1. Ir a: Jenkinsfile-prod
2. Click: "Build with Parameters"
3. Ingresar: IMAGE_TAG = prod-<SHA>
4. Click: "Build"
5. Aguardar aprobación en GitHub Environment "production"
6. Pipeline despliega a AKS prod (circleguard-prod-rg)

# Notificaciones:
# - Slack notification al completar
# - Alert a oncall si hay fallos
```

---

## 2. Rollback Procedures

### 2.1 Rollback Automático (Kubernetes)

**Caso: Deployment fallido / health checks fallan**

```bash
# Ver historial de rollouts
kubectl rollout history deployment/promotion-service -n circleguard-prod

# Ver detalles de una revisión anterior
kubectl rollout history deployment/promotion-service \
  -n circleguard-prod \
  --revision=2

# Rollback a la versión anterior
kubectl rollout undo deployment/promotion-service \
  -n circleguard-prod

# Rollback a revisión específica
kubectl rollout undo deployment/promotion-service \
  -n circleguard-prod \
  --to-revision=2

# Esperar a que complete
kubectl rollout status deployment/promotion-service \
  -n circleguard-prod \
  --timeout=300s
```

**Verificar após rollback:**

```bash
# Verificar pods están running
kubectl get pods -n circleguard-prod -l app=promotion-service

# Ver logs para errores
kubectl logs -n circleguard-prod \
  -l app=promotion-service \
  --tail=50

# Health check
curl -s http://promotion-service:8080/actuator/health | jq
```

---

### 2.2 Rollback Manual (Data / Database)

**Caso: Migrations corruptas / data inconsistency**

```bash
# 1. Detener pods
kubectl scale deployment/<service> --replicas=0 -n circleguard-prod

# 2. Restaurar from backup
# PostgreSQL
az postgres flexible-server restore \
  --resource-group circleguard-prod-rg \
  --name circleguard-postgres-restore \
  --source-server circleguard-postgres \
  --restore-time <BACKUP_TIMESTAMP>

# Neo4j
kubectl exec -it neo4j-pod -n circleguard-prod -- \
  neo4j-admin load --from=/backups/neo4j-backup-<DATE>.dump

# 3. Reiniciar pods
kubectl scale deployment/<service> --replicas=<NUM> -n circleguard-prod

# 4. Verificar data consistency
kubectl exec -it postgres-pod -n circleguard-prod -- \
  psql -U admin -d circleguard -c "SELECT COUNT(*) FROM users;"
```

---

## 3. Health Checks & Monitoring

### 3.1 Verificar Salud del Cluster

```bash
# Cluster status
kubectl cluster-info
kubectl get nodes -o wide

# Namespace status
kubectl get namespace
kubectl describe namespace circleguard-prod

# Pods status
kubectl get pods -n circleguard-prod
kubectl get pods -n circleguard-prod --field-selector=status.phase!=Running

# Services status
kubectl get svc -n circleguard-prod
kubectl get endpoints -n circleguard-prod
```

### 3.2 Verificar Middleware

```bash
# PostgreSQL
kubectl exec -it postgres-pod -n circleguard-prod -- \
  pg_isready -h localhost -p 5432

# Neo4j
kubectl exec -it neo4j-pod -n circleguard-prod -- \
  cypher-shell -u neo4j -p $NEO4J_PASSWORD "RETURN 1"

# Kafka
kubectl exec -it kafka-pod -n circleguard-prod -- \
  kafka-broker-api-versions.sh --bootstrap-server localhost:9092

# Redis
kubectl exec -it redis-pod -n circleguard-prod -- \
  redis-cli ping

# OpenLDAP
kubectl exec -it openldap-pod -n circleguard-prod -- \
  ldapsearch -h localhost -x -b "dc=circleguard,dc=edu" -s base
```

### 3.3 Verificar Servicios de Aplicación

```bash
# Gateway Service (entrypoint)
kubectl get pod -n circleguard-prod -l app=gateway-service
kubectl logs -n circleguard-prod -l app=gateway-service --tail=30

# Health endpoints
for svc in auth-service identity-service promotion-service form-service notification-service; do
  echo "=== $svc ==="
  kubectl exec -it svc/$svc -n circleguard-prod -- \
    curl -s http://localhost:8080/actuator/health | jq '.status'
done
```

---

## 4. Acceso a Herramientas de Observabilidad

### 4.1 Grafana (Dashboards)

**Port-forward:**

```bash
kubectl port-forward -n monitoring svc/grafana 3000:80
```

**Acceso:**

- URL: `http://localhost:3000`
- Usuario: `admin`
- Password: (obtener de secret)

```bash
kubectl get secret -n monitoring grafana \
  -o jsonpath="{.data.admin-password}" | base64 -d
```

**Dashboards principales:**

- **CircleGuard Overview:** Todos los servicios, latencia, error rate
- **Database Performance:** PostgreSQL y Neo4j metrics
- **Pod Resources:** CPU, memoria, I/O por pod
- **Network:** Throughput, latency (Istio metrics)

---

### 4.2 Kibana (Logs)

**Port-forward:**

```bash
kubectl port-forward -n monitoring svc/kibana 5601:5601
```

**Acceso:**

- URL: `http://localhost:5601`
- Login: Elasticsearch credentials

**Búsquedas comunes:**

```
# Errores en los últimos 1 hora
level:ERROR AND @timestamp:[now-1h TO now]

# Logs de un servicio específico
kubernetes.labels.app:promotion-service

# Latencia > 1s
@duration_ms:[1000 TO *]

# Trazas distribuidas (traceID)
traceID:abc123def456
```

---

### 4.3 Jaeger (Distributed Tracing)

**Port-forward:**

```bash
kubectl port-forward -n monitoring svc/jaeger-query 6831:16686
```

**Acceso:**

- URL: `http://localhost:16686`

**Análisis:**

1. Seleccionar servicio
2. Filtrar por operación (ej: POST /api/surveys)
3. Ver timeline de spans
4. Identificar servicios lentos

---

## 5. Chaos Engineering Experiments

### 5.1 PodChaos — Kill Pods

**Propósito:** Validar auto-healing y HPA

```bash
# Aplicar experimento
kubectl apply -f chaos/pod-chaos.yml

# Monitorear pods
kubectl get pods -n circleguard-stage -w

# Ver eventos del experimento
kubectl describe podchaos -n chaos-testing

# Eliminar experimento
kubectl delete -f chaos/pod-chaos.yml
```

**Expected behavior:**

- Pods se matan cada 2 minutos
- Readiness probes fallan
- Kubernetes reschedule automáticamente
- HPA escala si necesario
- No hay downtime de servicio

---

### 5.2 NetworkChaos — Latencia

**Propósito:** Validar retry policies y circuit breaker

```bash
# Aplicar experimento
kubectl apply -f chaos/network-chaos.yml

# Monitorear latencia
kubectl exec -it auth-service-pod -n circleguard-stage -- \
  curl -v http://identity-service:8080/api/health

# Ver circuit breaker state
kubectl port-forward svc/prometheus -n monitoring 9090:9090
# Luego query: envoy_cluster_circuit_breakers_default_rq

# Eliminar experimento
kubectl delete -f chaos/network-chaos.yml
```

**Expected behavior:**

- Latencia inyectada: 500ms
- Retry policies se activan (3 intentos)
- Circuit breaker NO se activa
- Timeout respetado (8 segundos)

---

### 5.3 StressChaos — CPU Stress

**Propósito:** Validar HPA y escalabilidad

```bash
# Aplicar experimento
kubectl apply -f chaos/stress-chaos.yml

# Monitorear HPA
kubectl get hpa -n circleguard-stage -w

# Ver escalado de replicas
kubectl get deploy -n circleguard-stage -w

# CPU usage
kubectl exec -it prometheus-pod -n monitoring -- \
  promtool query instant 'container_cpu_usage_seconds_total{pod="neo4j-0"}'

# Eliminar experimento
kubectl delete -f chaos/stress-chaos.yml
```

**Expected behavior:**

- CPU en Neo4j sube a 90%
- HPA detecta alta utilización
- Promotion-service escala a más replicas
- Alertas se disparan en Prometheus
- Graceful degradation sin 5xx errors

---

### 5.4 Ejecutar desde Jenkins

**Alternativa:** Ejecutar automáticamente con el pipeline

```bash
# En Jenkinsfile-staging:
1. Ir a "Build with Parameters"
2. Activar: RUN_CHAOS = true
3. Ingresar: IMAGE_TAG = staging-<SHA>
4. Build

# El pipeline ejecutará:
# - Deployment normal
# - Apply chaos experiments
# - Esperar 5 minutos
# - Monitorear comportamiento
# - Cleanup experiments
```

---

## 6. Troubleshooting Común

### 6.1 Pod CrashLoopBackOff

**Síntomas:** Pod reinicia continuamente

```bash
# Ver logs
kubectl logs <POD_NAME> -n circleguard-prod --previous

# Ver eventos
kubectl describe pod <POD_NAME> -n circleguard-prod

# Causas comunes:
# - Missing environment variables
# - Database connection failed
# - ConfigMap not found
# - Image pull error
```

**Solución:**

```bash
# Verificar ConfigMaps
kubectl get cm -n circleguard-prod

# Verificar Secrets
kubectl get secret -n circleguard-prod

# Verificar database connectivity
kubectl exec -it <POD_NAME> -n circleguard-prod -- \
  nc -zv postgres.circleguard-prod.svc.cluster.local 5432

# Rebuild y redeploy
kubectl set image deployment/<service> \
  <service>=cgregistry.azurecr.io/circleguard/<service>:<NEW_TAG> \
  -n circleguard-prod
```

---

### 6.2 Service Timeout / High Latency

**Síntomas:** Requests toman > 8 segundos

```bash
# Ver latency metrics
kubectl port-forward svc/prometheus -n monitoring 9090:9090
# Query: histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))

# Ver circuit breaker state
# Query: envoy_cluster_circuit_breakers_default_rq{cluster_name=~".*identity.*"}

# Ver Istio config
kubectl get vs -n circleguard-prod
kubectl describe vs <VS_NAME> -n circleguard-prod

# Ver retry policy
kubectl get vs <VS_NAME> -n circleguard-prod -o yaml | grep -A10 "retries"
```

**Solución:**

```bash
# Aumentar HPA limits si CPU alto
kubectl patch hpa promotion-service-hpa \
  -p '{"spec":{"maxReplicas":10}}' \
  -n circleguard-prod

# Aumentar timeout de Istio
kubectl patch vs <VS_NAME> -n circleguard-prod \
  --type merge \
  -p '{"spec":{"hosts":[{"timeout":"15s"}]}}'

# Escalar nodos del cluster
az aks scale \
  --resource-group circleguard-prod-rg \
  --name circleguard-prod \
  --node-count 6
```

---

### 6.3 Database Connection Pool Exhausted

**Síntomas:** "Too many connections" errors

```bash
# Ver connections actuales
kubectl exec -it postgres-pod -n circleguard-prod -- \
  psql -U admin -d circleguard \
  -c "SELECT count(*) FROM pg_stat_activity;"

# Ver idle connections
kubectl exec -it postgres-pod -n circleguard-prod -- \
  psql -U admin -d circleguard \
  -c "SELECT * FROM pg_stat_activity WHERE state='idle';"

# Ver pool status en Redis
kubectl exec -it redis-pod -n circleguard-prod -- \
  redis-cli info stats | grep connections
```

**Solución:**

```bash
# Aumentar max connections en Postgres
kubectl patch statefulset postgres \
  -p '{"spec":{"template":{"spec":{"containers":[{"name":"postgres","env":[{"name":"POSTGRES_MAX_CONNECTIONS","value":"200"}]}]}}}}' \
  -n circleguard-prod

# Reiniciar Postgres
kubectl rollout restart statefulset/postgres -n circleguard-prod

# Reducir idle timeout en aplicaciones
kubectl set env deployment/<service> \
  DATABASE_IDLE_TIMEOUT=60s \
  -n circleguard-prod
```

---

### 6.4 Disk Space Issues

**Síntomas:** PVC full, pods evicted

```bash
# Ver disk usage
kubectl exec -it <POD> -n circleguard-prod -- df -h

# Ver PVC status
kubectl get pvc -n circleguard-prod

# Ver tamaño de datos
kubectl exec -it postgres-pod -n circleguard-prod -- \
  du -sh /var/lib/postgresql/data

# Ver Neo4j database size
kubectl exec -it neo4j-pod -n circleguard-prod -- \
  du -sh /var/lib/neo4j/data
```

**Solución:**

```bash
# Resize PVC (si storage class lo soporta)
kubectl patch pvc postgres-pvc \
  -p '{"spec":{"resources":{"requests":{"storage":"100Gi"}}}}' \
  -n circleguard-prod

# Limpiar logs antiguos
kubectl exec -it <POD> -n circleguard-prod -- \
  find /logs -type f -mtime +7 -delete

# Trigger manual cleanup en PostgreSQL
kubectl exec -it postgres-pod -n circleguard-prod -- \
  psql -U admin -d circleguard -c "VACUUM ANALYZE;"
```

---

## 7. Incident Response Checklist

### Pre-Incident

- [ ] Página de status actualizada
- [ ] Runbooks documentados
- [ ] Alertas configuradas en Slack/email
- [ ] Oncall rotation establecida

### During Incident

- [ ] [ ] Declarar incident (SEV-1/SEV-2/SEV-3)
- [ ] [ ] Notificar al team
- [ ] [ ] Documentar timeline
- [ ] [ ] Recopilar logs/metrics
- [ ] [ ] Aplicar workaround temporal
- [ ] [ ] Comunicar a stakeholders

### Post-Incident

- [ ] [ ] Rootcause analysis (RCA)
- [ ] [ ] Post-mortem meeting
- [ ] [ ] Action items para prevenir recurrencia
- [ ] [ ] Update runbooks basado en learnings

---

## 8. Escalation Contacts

| Rol | Contacto | Horario |
|-----|----------|---------|
| **On-Call SRE** | Slack: #oncall | 24/7 |
| **Team Lead** | Slack: @lead | Business hours |
| **Database Admin** | Slack: @dba | Business hours |
| **Security Team** | security@circleguard.io | 24/7 |

---

## Referencias

- [Architecture Overview](./architecture.md)
- [Change Management Process](./change-management.md)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Istio Service Mesh](https://istio.io/latest/docs/)
- [Chaos Mesh Documentation](https://chaos-mesh.org/docs/)
