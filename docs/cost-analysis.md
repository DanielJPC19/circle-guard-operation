# Cost Analysis & FinOps Strategy

## Resumen Ejecutivo

CircleGuard está desplegado en **Microsoft Azure (AKS)** para todos los ambientes (dev, staging, prod). Este documento detalla el análisis de costos actuales basados en la arquitectura Azure real y estrategias de ahorro implementadas mediante KEDA.

---

## Desglose de Costos Reales

### Tabla de Costos por Ambiente (Mensual — Estimados)

| Ambiente | Servicio | Configuración | Costo estimado/mes | Notas |
|----------|---------|---------------|-------------------|-------|
| **DEV** | AKS (circleguard-dev) | 1x Standard_D2s_v3 | $70 | Con KEDA scale-to-zero |
| **STAGING** | AKS (circleguard-stage) | 1x Standard_D2s_v3 | $70 | HPA 2-4 replicas |
| **PROD** | AKS (circleguard-prod) | 1x Standard_D2s_v3 | $70 | HPA 2-8 replicas |
| **Registry** | ACR (cgregicesi) | Premium tier + almacenamiento | $20 | Compartido entre ambientes |
| **TOTAL** | **Azure AKS** | **3 nodos Standard + ACR** | **~$230/mes** | Estimado |

**Nota:** Estos valores son **estimaciones** basadas en precios públicos de Azure. Los costos reales pueden variar según uso de ancho de banda, almacenamiento persistente, e IPs públicas. Se recomienda usar **Kubecost** (instalado en el cluster) para monitoreo en tiempo real.

---

### Desglose Detallado por Ambiente

#### AKS Development (circleguard-dev)

```
Compute:
  - 1x VM Standard_D2s_v3 (2 vCPU, 8 GB RAM): ~$70/mes

Storage:
  - Managed disks para estado (PostgreSQL, Neo4j): incluido en VM

Networking:
  - Ingress/Load Balancer: incluido en AKS

Total DEV: ~$70/mes
```

**Optimizaciones activas:**
- KEDA scale-to-zero para promotion-service → reduce carga cuando inactivo
- 1 nodo base con autoscaling a máximo 3

---

#### AKS Staging (circleguard-stage)

```
Compute:
  - 1x VM Standard_D2s_v3 (2 vCPU, 8 GB RAM): ~$70/mes

Networking & Load Balancing:
  - Standard Load Balancer: incluido

Total STAGING: ~$70/mes
```

**Configuración:**
- HPA 2-4 replicas
- Health checks cada 15 segundos
- Readiness probes para drenaje de tráfico

---

#### AKS Production (circleguard-prod)

```
Compute:
  - 1x VM Standard_D2s_v3 (2 vCPU, 8 GB RAM): ~$70/mes

Networking:
  - Load Balancer + Ingress controller: incluido

Total PROD: ~$70/mes
```

**Configuración:**
- HPA 2-8 replicas con podAntiAffinity
- Istio mTLS STRICT
- PodDisruptionBudgets

---

#### Azure Container Registry (cgregicesi)

```
Registro Premium: ~$20/mes
  - Almacenamiento: ~500 MB (8 servicios × 60 MB cada uno)
  - Transfers salientes: ~5 GB/mes (pulls desde clusters)

Total ACR: ~$20/mes
```

---

## Estrategias de Ahorro Implementadas

### 1. KEDA Scale-to-Zero en Development

**Objetivo:** Reducir costos en desarrollo escalando promotion-service a cero replicas cuando no hay demanda.

**Configuración:**
```yaml
# k8s/services/dev/keda-scaled-objects.yml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: promotion-service-scaler
  namespace: circleguard-dev
spec:
  minReplicaCount: 0              # Scale to zero cuando lag = 0
  maxReplicaCount: 3              # Máximo 3 replicas bajo carga
  triggers:
    - type: kafka
      metadata:
        topic: health-status-events
        lagThreshold: "5"           # Escala up cuando >5 mensajes en backlog
```

**Impacto esperado:**
- **Reducción estimada: 15-20%** en costos de DEV (servicios solo activos bajo demanda)
- Ahorro mensual estimado: ~$10-15/mes
- Pod requests reducidos cuando scale-to-zero activo

**Monitoreo:**
```promql
# Verificar escalado de KEDA
keda_scaler_active{scaler="promotion-service-scaler"}

# Historial de replicas
increase(keda_scaler_scaled[5m])
```

---

### 2. HPA (Horizontal Pod Autoscaler)

**En staging y producción:** HPA automático basado en CPU/memoria.

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: promotion-service-hpa
  namespace: circleguard-prod
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: promotion-service
  minReplicas: 2
  maxReplicas: 8
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
```

---

### 3. Kubecost — Monitoreo de Costos Real

**Instalado en:** `monitoring` namespace

**Acceso:** Dashboards Grafana con desglose por:
- Proveedor (Azure)
- Namespace (circleguard-dev, circleguard-stage, circleguard-prod)
- Pod/Deployment
- Request vs actual allocation

**Comando para consultar costos:**
```bash
kubectl port-forward -n monitoring svc/kubecost 9090:9090
# Abrir: http://localhost:9090
```

---

## Proyecciones de Costos

### Costo Anual Estimado (sin optimizaciones adicionales)

```
DEV:      $70  × 12 = $840/año
STAGING:  $70  × 12 = $840/año
PROD:     $70  × 12 = $840/año
ACR:      $20  × 12 = $240/año
──────────────────────────────
TOTAL:   $230 × 12 = $2,760/año
```

### Oportunidades de Ahorro Futuro

| Estrategia | Ahorro potencial | Estado | Prioridad |
|-----------|-----------------|--------|-----------|
| **KEDA Scale-to-Zero (DEV)** | $15-20/mes | ✅ Implementado | Alta |
| **Reserved Instances (1-year)** | 15% anual | ⏳ Recomendado | Media |
| **Spot/Preemptible VMs** | 20-30% | ⏳ Futuro | Media |
| **Right-sizing por Kubecost** | 5-10% | ⏳ Evaluar | Baja |

---

## Benchmarks y Comparativas

**Referencia:** Los costos de Azure AKS son altamente competitivos en la región elegida (East US, South Central US). Para futuras evaluaciones, consultar:
- [Azure Pricing Calculator](https://azure.microsoft.com/en-us/pricing/calculator/)
- [Kubecost Documentation](https://docs.kubecost.com/)

---

## Conclusión

CircleGuard opera con **costo estimado de ~$230/mes en Azure AKS**. Las estrategias implementadas (KEDA, HPA) reducen costos operativos. Se recomienda monitoreo continuo vía Kubecost para identificar oportunidades adicionales.

**Última actualización:** 2026-06-12
**Documento:** Cost Analysis & FinOps Strategy
**Estado:** ✅ Basado en arquitectura Azure real

