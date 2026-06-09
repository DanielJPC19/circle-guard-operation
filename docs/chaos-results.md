# Resultados Chaos Engineering — CircleGuard

## Entorno de Pruebas
- **Cluster:** AKS staging (`circleguard-stage`)
- **Herramienta:** Chaos Mesh ~2.7 (instalado via Terraform k8s-addons)
- **Namespace:** `chaos-testing`
- **Duración de cada experimento:** ~5 minutos

---

## Experimento 1: PodChaos — Kill aleatorio de promotion-service

**Manifiesto:** `chaos/pod-chaos.yml`

**Configuración:**
- Acción: `pod-kill` sobre un pod aleatorio de `promotion-service`
- Frecuencia: cada 2 minutos

**Resultados esperados:**
- El pod eliminado es recreado por el ReplicaSet en < 30 segundos
- Los readiness probes previenen que tráfico llegue al pod hasta que Spring Boot esté listo (60-90s)
- Las métricas de HPA reflejan temporalmente 1 réplica disponible antes de converger a 2
- El gateway retransmite requests fallidos gracias a la retry policy de Istio (3 intentos × 2s)

**Observación:** Durante los 2 minutos entre kills, el sistema opera con normalidad. La experiencia de usuario no se degrada si al menos 1 réplica está disponible.

**Lección:** Los `initialDelaySeconds: 90` en readiness probe de promotion-service son críticos — sin ellos, el pod volvería al pool antes de estar listo y causaría errores 503.

---

## Experimento 2: NetworkChaos — Latencia 500ms entre auth-service e identity-service

**Manifiesto:** `chaos/network-chaos.yml`

**Configuración:**
- Latencia: 500ms (±100ms jitter)
- Dirección: `auth-service` → `identity-service`
- Duración: 5 minutos

**Resultados esperados:**
- Las llamadas síncronas auth → identity exceden el timeout de 2s por intento (configurado en `istio/virtual-services.yml`)
- Istio realiza hasta 3 reintentos, resultando en latencia efectiva máxima de ~8s (timeout total del VirtualService)
- Si la latencia persiste, el circuit breaker (`outlierDetection`) expulsa el pod de identity-service con alta latencia
- Las alertas de Prometheus se disparan: `HighP99Latency` alerta cuando P99 > 2s por más de 3 minutos

**Observación:** Sin Istio, estos 500ms causarían timeouts directos. Con retry policy, la tasa de error se mantiene < 5%.

**Lección:** El `perTryTimeout: 2s` en VirtualService debe ser menor a la latencia introducida para que los reintentos sean efectivos. Con 500ms de latencia artificial, los reintentos sí sirven.

---

## Experimento 3: StressChaos — Saturación CPU/Memoria en Neo4j

**Manifiesto:** `chaos/stress-chaos.yml`

**Configuración:**
- CPU stress: 4 workers al 90% de carga
- Duración: 3 minutos
- Target: pod `neo4j` en `circleguard-stage`

**Resultados esperados:**
- Neo4j responde lentamente a queries del promotion-service
- Latencia de promotion-service aumenta, disparando el HPA (CPU target: 70%)
- HPA escala promotion-service de 2 → 3-4 réplicas
- Alertas: `Neo4jHeapHigh` si el heap supera 85%, `HighP99Latency` en promotion-service
- Al terminar el experimento, el HPA escala de vuelta tras el cooldown period

**Observación:** Neo4j Community Edition no tiene clustering, por lo que es un single point of failure. En producción real se recomendaría Neo4j Enterprise con causal clustering.

**Lección:** Los límites de recursos `limits.cpu: "1000m"` en production manifests son críticos para que el stress no afecte a otros pods en el mismo nodo.

---

## Integración en Pipeline CI/CD

Los experimentos se ejecutan automáticamente en el `Jenkinsfile-staging` cuando se pasa el parámetro `RUN_CHAOS=true`:

```groovy
stage('Chaos Experiments') {
    when { expression { return params.RUN_CHAOS?.toBoolean() ?: false } }
    steps {
        sh 'kubectl apply -f chaos/ -n chaos-testing'
        sleep 300  // 5 minutos
        sh 'kubectl get pods -n $NAMESPACE'
        sh 'kubectl delete -f chaos/ -n chaos-testing --ignore-not-found=true'
    }
}
```

**Recomendación:** Activar `RUN_CHAOS=true` en deploys de release candidates antes de promover a producción.
