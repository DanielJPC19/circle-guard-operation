# Evaluación de Proveedores Cloud — Decisión: Azure (AKS)

Análisis de opciones consideradas para la infraestructura de CircleGuard. Se evaluaron tres proveedores (DigitalOcean DOKS, Microsoft Azure AKS, Google Cloud GKE), siendo **Azure AKS seleccionado para todos los ambientes** (dev, staging, prod).

---

## Resumen de Decisión

| Aspecto | Consideración | Decisión |
|--------|---------------|----------|
| **Proveedor seleccionado** | DOKS, AKS, GKE evaluados | ✅ **Azure AKS** (todos los ambientes) |
| **Razón principal** | Disponibilidad de créditos Azure, familiaridad del equipo, integración ACR | Despliegue 100% AKS |
| **Ambientes implementados** | dev, staging, prod | Todos en **AKS** |
| **Estado Terraform** | Azure Blob Storage (`cgtfstate`) | Azure |
| **Credenciales** | Service principal Azure | `azure-sp-credentials` |

---

## 1. Opciones Evaluadas (Análisis Previo a Decisión)

A continuación se presentan las características de cada proveedor que fueron consideradas durante la fase de planificación.

### 1.1 Costos Estimados por Proveedor (no medidos en producción)

Estos son costos **estimados** basados en precios públicos de cada proveedor en el momento de evaluación:

| Proveedor | Nodos | Configuración | Costo estimado | Notas |
|-----------|-------|---------------|-----------------|-------|
| **DigitalOcean DOKS** | 1 | Compute-optimized (4vCPU, 8GB) | ~$48/mes | Opción de bajo costo, KEDA para scale-to-zero |
| **Microsoft Azure AKS** | 1-3 | Standard_D2s_v3 (2vCPU, 8GB) | ~$140/mes | Opción seleccionada, ACR integrado |
| **Google Cloud GKE** | 3 | n1-standard-2 (2vCPU, 7.5GB) | ~$230/mes | Opción premium, SLO 99.95% |

**Nota importante:** Estos valores son **estimaciones públicas previas a implementación**, no costos reales medidos. El proyecto se desplegó completamente en Azure AKS.

### 1.2 Características Técnicas Comparadas

| Métrica | DOKS | AKS | GKE |
|---------|------|-----|-----|
| **SLA ofrecido** | 99.0% | 99.95% | 99.95% |
| **Madurez Kubernetes** | Estable | Muy madura (integración Azure) | Muy madura (origen K8s) |
| **Integración nativa** | Docker Hub Registry | Azure Container Registry (ACR) | Google Container Registry (GCR) |
| **Herramientas nativas** | Limitadas | Azure Monitor, Azure AD | Cloud Logging, Cloud Monitoring |
| **Istio Support** | Sí (manual) | Sí (manual) | Sí (GKE Dataplane) |
| **RBAC** | Sí | Sí (integrado Azure AD) | Sí |

---

## 2. Factores de Decisión

### 2.1 Criterios Cualitativos

**Se eligió Azure AKS por:**

1. **Disponibilidad de recursos:** El equipo contaba con créditos Azure y acceso existente
2. **Familiaridad del equipo:** Experiencia previa con Azure ecosistema
3. **Integración con ACR:** Azure Container Registry incluido y nativo para AKS
4. **Certificación y compliance:** Facilidades en Azure para cumplimiento institucional
5. **Soporte organizacional:** IT institucional con soporte Azure establecido

### 2.2 Por qué NO se eligieron las otras opciones

**DigitalOcean DOKS:**
- Menor SLA (99.0% vs 99.95%)
- Registry separado o terceros
- Menor integración de herramientas nativas
- Equipo sin experiencia previa

**Google Cloud GKE:**
- Mayor costo estimado
- Falta de credenciales/acceso GCP
- No alineado con infraestructura existente

---

## 3. Infraestructura Implementada (Real)

**Todos los ambientes desplegados en Azure AKS:**

```
CircleGuard v1.0.0 — Topología Real
├── DEV        → AKS (circleguard-dev)    [1 nodo Standard_D2s_v3]
├── STAGING    → AKS (circleguard-stage)  [1 nodo Standard_D2s_v3]
└── PROD       → AKS (circleguard-prod)   [1 nodo Standard_D2s_v3]

Estado Terraform: Azure Blob Storage (cgtfstate storage account)
Autenticación CD: Azure Service Principal (azure-sp-credentials)
Registry: Azure Container Registry (cgregicesi.azurecr.io)
```

### 3.1 Módulos Terraform Implementados

```
infra/modules/
├── aks/         ← provider: azurerm
├── acr/         ← provider: azurerm
└── k8s-addons/  ← Helm (agnóstico de cloud)
```

**NO existen módulos** para DOKS (`infra/modules/doks/`) ni GKE (`infra/modules/gke/`).

### 3.2 Jenkinsfiles — Autenticación Real

**Jenkinsfile-staging (línea 44-46):**
```bash
az aks get-credentials \
    --resource-group $AKS_RG \
    --name $AKS_CLUSTER
```

**Jenkinsfile-prod (línea 43-46):**
```bash
az aks get-credentials \
    --resource-group $AKS_RG \
    --name $AKS_CLUSTER
```

**Credenciales usadas:** `azure-sp-credentials`, `az-tenant-id` (Azure únicamente)

---

## 4. Lecciones Aprendidas

1. **Consolidación en un proveedor:** Simplifica operaciones, reduce complejidad de CI/CD
2. **IaC modular:** Aunque es AKS, los módulos Terraform en `infra/modules/` son reutilizables
3. **Backend remoto:** Azure Blob Storage (`cgtfstate`) centraliza estado para todos los ambientes
4. **ACR como registry:** Integración nativa con AKS acelera deploys

---

## Metadata

- **Documento:** Evaluación de Proveedores Cloud
- **Decisión:** Azure AKS para todos los ambientes (dev, staging, prod)
- **Implementado:** ✅ 100% Azure
- **Fecha evaluación:** 2026-06-11
- **Estado:** Versión 1.0.0

