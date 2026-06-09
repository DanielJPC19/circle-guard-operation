# Comparativa Multi-Cloud — DOKS vs AKS vs GKE

Análisis estratégico de la decisión de usar 3 proveedores diferentes para desarrollo, staging y producción en CircleGuard.

---

## Resumen Ejecutivo

| Proveedor | Ambiente | Razón | Costo Mensual | Escala |
|-----------|----------|-------|---------------|--------|
| **Digital Ocean DOKS** | Development | Bajo costo, simplicidad | $48 | 1 nodo + KEDA 0-3 |
| **Microsoft Azure AKS** | Staging | ACR integrado, corp familiar | $140 | 2-5 nodos auto-scale |
| **Google Cloud GKE** | Production | Madurez, SLO 99.95%, CUD | $230 | 3-8 nodos auto-scale |

**Ahorro Total Potencial:** 45% ($197/mes) mediante optimizaciones.

---

## 1. Tabla Comparativa Detallada

### 1.1 Costo

| Aspecto | DOKS (Dev) | AKS (Staging) | GKE (Prod) |
|---------|-----------|--------------|-----------|
| **Costo Compute (base)** | $48/mes | $140/mes | $230/mes |
| **Descuentos** | KEDA -40% | Autoscaling -20% | CUD -30% |
| **Costo Final** | $29/mes | $112/mes | $161/mes |
| **Costo por nodo** | $48 (1) | $70 (2) | $77 (3) |
| **PV Storage 50GB** | Incluido | $10 | $15 |
| **Load Balancer** | Incluido | $5 | $15 |
| **Service Mesh (Istio)** | Gratis | Gratis | Gratis |

**Nota:** Costos sin optimizaciones adicionales. Kubecost proporciona alertas de oportunidades.

---

### 1.2 Rendimiento & SLA

| Métrica | DOKS | AKS | GKE |
|---------|------|-----|-----|
| **SLA Cluster** | 99.0% | 99.95% | 99.95% |
| **Latencia (región)** | us-nyc1 | East US | us-central1 |
| **API Server availability** | 99% | 99.95% | 99.95% |
| **Networking Throughput** | Hasta 10 Gbps | Hasta 25 Gbps | Hasta 100 Gbps |
| **Pod density** | Bajo (~40 pods/nodo) | Medio (~80 pods/nodo) | Alto (~120 pods/nodo) |
| **Network latency** | 10-20ms | 5-15ms | 5-10ms |

---

### 1.3 Tipos de Nodos Disponibles

#### DOKS
```
- Compute-Optimized: 4 vCPU, 8GB RAM = $48/mes
- General Purpose: 2 vCPU, 2GB RAM = $12/mes
- Memory-Optimized: 8 vCPU, 32GB RAM = $96/mes
```

#### AKS
```
- Standard_D2s_v3: 2 vCPU, 8GB RAM = $70/mes (usado)
- Standard_D4s_v3: 4 vCPU, 16GB RAM = $140/mes
- Memory-Optimized: E4s_v3, 4 vCPU, 32GB RAM = $195/mes
```

#### GKE
```
- n1-standard-1: 1 vCPU, 3.75GB RAM = $42/mes
- n1-standard-2: 2 vCPU, 7.5GB RAM = $77/mes (usado)
- n1-standard-4: 4 vCPU, 15GB RAM = $154/mes
- e2-standard-2: 2 vCPU, 8GB RAM = $58/mes (buena relación precio/performance)
```

---

### 1.4 Escalabilidad

| Aspecto | DOKS | AKS | GKE |
|---------|------|-----|-----|
| **Horizontal Pod Scaling** | KEDA 0-3 | HPA 2-4 | HPA 2-8 |
| **Cluster Autoscaling** | Manual | 2-5 nodos | 3-8 nodos |
| **Max Pods/Cluster** | 500 | 5,000+ | 5,000+ |
| **Max Nodes/Cluster** | 100 | 1,000 | 1,000 |
| **Node Pool Multi-zona** | No | Sí | Sí |
| **Scale-to-zero support** | KEDA | No (mín 2) | No (mín 3) |

---

### 1.5 Características de Kubernetes

| Feature | DOKS | AKS | GKE |
|---------|------|-----|-----|
| **K8s Version** | 1.29+ | 1.29+ | 1.29+ |
| **Network CNI** | Flannel | Azure CNI | GCP VPC |
| **Ingress Controller** | Nginx | Nginx/Azure | Gcloud Ingress |
| **Service Mesh** | Instalable | Instalable | Instalable (GKE Dataplane) |
| **Istio Support** | Sí | Sí | Sí (native) |
| **RBAC** | Sí | Sí (integrado Azure AD) | Sí |
| **Network Policies** | Sí | Sí | Sí |
| **Pod Security Policies** | Sí | Sí | Sí |

---

### 1.6 Integración Nativa

| Aspecto | DOKS | AKS | GKE |
|---------|------|-----|-----|
| **Container Registry** | Docker Hub, Digital Ocean Registry | **Azure Container Registry (ACR)** | Google Container Registry (GCR) |
| **Secrets Management** | Sealed Secrets | Azure Key Vault | Google Secret Manager |
| **Logging** | ELK Stack (manual) | Azure Monitor Logs | Cloud Logging (integrado) |
| **Monitoring** | Prometheus + Grafana | Azure Monitor | Cloud Monitoring (integrado) |
| **DNS** | Digital Ocean DNS | Azure DNS | Google Cloud DNS |
| **Load Balancer** | Load Balancer Services | Azure LB | Google Cloud LB |

---

### 1.7 Soporte & Madurez

| Aspecto | DOKS | AKS | GKE |
|---------|------|-----|-----|
| **Madurez Producto** | Estable (2020+) | Muy madura (2017+) | Muy madura (2015+, primer K8s en prod) |
| **SLA Support** | Estándar | Premium disponible | Premium disponible |
| **Documentation** | Buena | Excelente | Excelente |
| **Community** | Activa | Muy activa | Muy activa |
| **Security Updates** | Regulares | Frecuentes | Frecuentes |
| **Price Predictability** | Alta | Media | Alta (CUD) |

---

## 2. Ventajas y Desventajas por Proveedor

### 2.1 Digital Ocean DOKS (Development)

**Ventajas:**
- ✅ **Costo muy bajo** ($48/mes sin optimizaciones)
- ✅ **KEDA scale-to-zero** compatible → Ahorro 40% adicional
- ✅ **Simplicidad operacional** → Menos configuración
- ✅ **Managed Kubernetes** con buen uptime
- ✅ **Buena documentación** para equipos pequeños

**Desventajas:**
- ❌ **SLA inferior** (99% vs 99.95%)
- ❌ **Escalabilidad limitada** → Máx 1 nodo en dev
- ❌ **Pod density baja** → Menos capacidad de compresión
- ❌ **No multi-zona** → Single point of failure
- ❌ **Menos integraciones nativas**

**Caso de Uso:**
- Desarrollo local y testing
- Ambientes efímeros
- Equipos que necesitan aprender K8s sin costo alto

---

### 2.2 Microsoft Azure AKS (Staging)

**Ventajas:**
- ✅ **ACR integrado** → Registry privado sin costo adicional
- ✅ **Familiar para empresas** con Windows/Office 365
- ✅ **Azure AD integration** → SSO corporativo
- ✅ **Buena escalabilidad** → 2-5 nodos automático
- ✅ **Networking predecible** → Azure CNI completo
- ✅ **Buen precio** en empresas con Visual Studio licenses

**Desventajas:**
- ❌ **Complejidad operacional** → Muchas opciones de configuración
- ❌ **Menos maduro que GKE** → Menos features K8s nativas
- ❌ **Vendor lock-in** → AD, Key Vault, Azure Monitor
- ❌ **SLO no está incluido** en el paquete base
- ❌ **Networking puede ser confuso** → Multiple peering options

**Caso de Uso:**
- Staging para validar antes de producción
- Organizaciones con inversión en Azure/Microsoft
- Equipos que necesitan corporate SSO

---

### 2.3 Google Cloud GKE (Production)

**Ventajas:**
- ✅ **SLA 99.95%** con garantía de uptime
- ✅ **Madurez máxima** → K8s nació en Google
- ✅ **Mejor rendimiento** → Cloud Networking superior
- ✅ **Cost optimization** → CUD 52% descuento posible
- ✅ **Istio nativo** → GKE Dataplane option
- ✅ **Observabilidad integrada** → Cloud Logging, Cloud Monitoring
- ✅ **Security** → Advanced threat detection, Binary Authorization
- ✅ **Scaling automático robusto** → 3-8 nodos fácil

**Desventajas:**
- ❌ **Costo base más alto** ($230/mes)
- ❌ **Learning curve mayor** → Más opciones que otros
- ❌ **Potential vendor lock-in** → GCP ecosystem
- ❌ **Requiere ingeniería especializada**

**Caso de Uso:**
- **Production crítico** con SLA requerido
- Aplicaciones que demandan máxima disponibilidad
- Organizaciones con equipo DevOps experimentado

---

## 3. Matriz de Decisión: ¿Cuál Proveedor Elegir?

### Criterios

| Criterio | Peso | DOKS | AKS | GKE |
|----------|------|------|-----|-----|
| **Costo total** | 30% | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ |
| **Rendimiento** | 20% | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| **Escalabilidad** | 15% | ⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| **SLA/Disponibilidad** | 20% | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| **Ease of Ops** | 10% | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ |
| **Integraciones Nativas** | 5% | ⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |

**Conclusión:** CircleGuard eligió correctamente usar **DOKS+AKS+GKE** como estrategia **multi-cloud** para:
- Minimizar costo en dev (DOKS)
- Validar cambios antes de prod (AKS)
- Garantizar SLA en producción (GKE)

---

## 4. Estrategia por Ambiente (CircleGuard)

### 4.1 Development (DOKS)

**Objetivo:** Máximo ahorro, flexibilidad de experimentación

```
Configuración:
├─ 1 nodo compute-optimized ($48/mes)
├─ KEDA ScaledObjects (scale-to-zero)
├─ HPA deshabilitado (para evitar overhead)
├─ Sealed Secrets local (no sincronización)
├─ Logging simple (ELK Stack)
└─ No multi-zona (single AZ)

Justificación:
- Usado por developers
- Ciclo iterativo rápido
- Costo es factor clave
- Downtime aceptable (solo dev)
- Scale-to-zero ahorra 40% → $29/mes
```

---

### 4.2 Staging (AKS)

**Objetivo:** Validar cambios con infraestructura production-like

```
Configuración:
├─ 2-5 nodos auto-scaling (Standard_D2s_v3)
├─ HPA 2-4 replicas (más que dev)
├─ Azure Container Registry (ACR)
├─ Multi-zona dentro de región (availability zones)
├─ ELK Stack central + Azure Monitor
├─ Sealed Secrets sincronizadas (pre-prod)
└─ Istio service mesh (test mTLS antes de prod)

Justificación:
- Espejo de producción en escala smaller
- Validar deploys antes de prod
- Test performance under load
- ACR es familiar para team
- SLA no crítico pero verificado (99.95%)
```

---

### 4.3 Production (GKE)

**Objetivo:** Máxima resiliencia y SLA

```
Configuración:
├─ 3-8 nodos auto-scaling (n1-standard-2)
├─ Multi-zona (3 AZs en us-central1)
├─ HPA 2-8 replicas aggressive
├─ Committed Use Discounts (52% - 3 year)
├─ Cloud Logging + Cloud Monitoring
├─ Sealed Secrets synced con Google Secret Manager
├─ Istio strict mTLS (all traffic encrypted)
├─ Pod anti-affinity required (spread across nodes)
├─ Network policies enforced
└─ SLA 99.95% guaranteed

Justificación:
- Crítica para negocio
- Downtime = revenue loss
- SLA requerido contractualmente
- Google es pioneer de Kubernetes
- CUD para optimizar costo (30% discount)
- Máxima seguridad y observabilidad
```

---

## 5. Roadmap Alternativo (Si Solo Fuera Uno)

### Opción A: GKE Everywhere (Google Cloud)

**Pro:**
- Simplicidad operacional (un solo proveedor)
- Mejor SLA en todos lados
- Cloud Logging/Monitoring en todos lados
- Menos "glue code" entre clouds

**Contra:**
- Costo dev es $230/mes (vs $48 DOKS)
- Potential vendor lock-in
- Dev team no aprende azure

**Costo:** ~$600/mes (prod $230, staging $230, dev $140)

---

### Opción B: Azure Everywhere (AKS)

**Pro:**
- ACR en todos lados
- Azure AD everywhere
- Consistent Azure ecosystem

**Contra:**
- AKS menos maduro que GKE
- SLA inferior (99.95% pero menos track record)
- Costo similar a GKE ($400-500/mes total)

**Costo:** ~$500/mes

---

### Opción C: Multi-Cloud Strategy (CircleGuard Actual)

**Pro:**
- ✅ Máximo ahorro ($345/mes implementado, $241 optimizado)
- ✅ Avoid vendor lock-in
- ✅ Team aprender 3 ecosistemas
- ✅ Resiliencia: si un proveedor falla, otros 2 funcionan

**Contra:**
- ❌ Complexity (3 CLIs, 3 authentication methods)
- ❌ Operational overhead (3 flavors de K8s)
- ❌ Terraform complexity

**Costo:** ~$345/mes (implementado), ~$241/mes (optimizado -30%)

**Recomendación:** Multi-cloud es correcto para CircleGuard porque:
1. Costo es prioritario para startup
2. Team tiene capacity para complejidad
3. Vendor independence es valioso
4. Poder aprender GCP, Azure, DigitalOcean es habilidad

---

## 6. Migration Path (Si Cambiar Proveedor)

### 6.1 Migrar Dev de DOKS a GKE

```bash
# 1. Setup GKE cluster
gcloud container clusters create circleguard-dev-gke \
  --machine-type n1-standard-1 \
  --num-nodes 1 \
  --zone us-central1-a

# 2. Aplicar manifests existentes
kubectl apply -f k8s/namespaces/circleguard-dev.yml
kubectl apply -f k8s/infra/ -n circleguard-dev
kubectl apply -f k8s/services/dev/ -n circleguard-dev

# 3. Migrar data (if needed)
kubectl exec -it postgres-doks -n circleguard-dev -- \
  pg_dump circleguard | \
  kubectl exec -i postgres-gke -n circleguard-dev -- \
  psql circleguard

# 4. Update kubeconfig
gcloud container clusters get-credentials circleguard-dev-gke

# 5. Cleanup DOKS
doctl kubernetes cluster delete circleguard-dev
```

---

### 6.2 Migrar Staging de AKS a GKE

**Similar process pero con más cautela:**
- Backup AKS data
- Canary deploy a GKE (10%)
- Gradual traffic shift
- Rollback plan ready

---

## 7. Cost Optimization Checklist

### Immediate (implementado)
- [x] KEDA scale-to-zero en dev → -40%
- [x] Cluster autoscaling en staging/prod → -20%

### Short-term (1-3 meses)
- [ ] CUD 1-year en GKE prod → -25%
- [ ] Right-sizing nodos via Kubecost → -15%

### Medium-term (3-6 meses)
- [ ] Spot/Preemptible instances en dev → -50%
- [ ] Multi-region pod autoscaling → -10%

### Long-term (6-12 meses)
- [ ] CUD 3-year en GKE prod → -52%
- [ ] Reserved Instances en AKS → -30%

**Target:** -45% total from current baseline

---

## Referencias

- [Cost Analysis](./cost-analysis.md)
- [Architecture Overview](./architecture.md)
- [DigitalOcean Pricing](https://www.digitalocean.com/pricing/)
- [Azure AKS Pricing](https://azure.microsoft.com/en-us/pricing/details/kubernetes-service/)
- [GCP GKE Pricing](https://cloud.google.com/kubernetes-engine/pricing)
- [Kubecost Documentation](https://docs.kubecost.com/)
