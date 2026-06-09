# Patrones de Diseño en CircleGuard

Este documento describe los patrones de diseño implementados en la arquitectura de microservicios de CircleGuard, con ejemplos reales del código base.

---

## 1. Repository Pattern

### Ubicación
- **Proyecto:** circle-guard-development (todos los servicios)
- **Ejemplo:** `circleguard-promotion-service/src/main/java/com/circleguard/promotion/repository/`
- **Interfaces:** `LocalUserRepository.java`, `HealthSurveyRepository.java`, `UserNodeRepository.java`

### Descripción
El Repository Pattern proporciona una abstracción para acceso a datos, desacoplando la lógica de negocio de la persistencia.

### Código de Ejemplo
```java
// circleguard-promotion-service/src/main/java/com/circleguard/promotion/repository/jpa/
public interface HealthSurveyRepository extends JpaRepository<HealthSurvey, UUID> {
    List<HealthSurvey> findByAttachmentPathIsNotNullAndValidationStatus(ValidationStatus status);
    Optional<HealthSurvey> findByAnonymousId(UUID anonymousId);
}

// En el servicio
@Service
@RequiredArgsConstructor
public class HealthSurveyService {
    private final HealthSurveyRepository repository;

    @Transactional
    public HealthSurvey submitSurvey(HealthSurvey survey) {
        return repository.save(survey);
    }
}
```

### Beneficio Obtenido
- Abstracción clara entre servicios y datos
- Facilita testing con mocks
- Permite cambiar la estrategia de persistencia sin modificar lógica de negocio
- Soporte para múltiples bases de datos (JPA para SQL, Neo4j para grafo)

---

## 2. Factory Pattern

### Ubicación
- **Proyecto:** circle-guard-development
- **Servicio:** circleguard-auth-service
- **Clase:** `com.circleguard.auth.security.DualChainAuthenticationProvider.java`

### Descripción
El Factory Pattern proporciona un mecanismo para instanciar el proveedor de autenticación correcto según el tipo de usuario (LDAP o Base de Datos Local).

### Código de Ejemplo
```java
// circleguard-auth-service/src/main/java/com/circleguard/auth/security/DualChainAuthenticationProvider.java
@Component
@RequiredArgsConstructor
public class DualChainAuthenticationProvider implements AuthenticationProvider {

    private final LdapAuthenticationProvider ldapProvider;
    private final DaoAuthenticationProvider localProvider;

    @Override
    public Authentication authenticate(Authentication authentication) throws AuthenticationException {
        try {
            // Chain 1: Try LDAP (para usuarios del directorio corporativo)
            return ldapProvider.authenticate(authentication);
        } catch (AuthenticationException e) {
            // Chain 2: Fallback a Local DB (para usuarios locales)
            return localProvider.authenticate(authentication);
        }
    }

    @Override
    public boolean supports(Class<?> authentication) {
        return UsernamePasswordAuthenticationToken.class.isAssignableFrom(authentication);
    }
}
```

### Beneficio Obtenido
- Soporte transparente para múltiples mecanismos de autenticación
- Fallback automático si LDAP no está disponible
- Centraliza la lógica de decisión de instantiación
- Facilita agregar nuevos proveedores de autenticación

---

## 3. Observer Pattern

### Ubicación
- **Proyecto:** circle-guard-development
- **Implementación:** Eventos asíncronos mediante Apache Kafka
- **Listeners:**
  - `circleguard-promotion-service/src/main/java/com/circleguard/promotion/listener/SurveyListener.java`
  - `circleguard-notification-service/src/main/java/com/circleguard/notification/service/ExposureNotificationListener.java`

### Descripción
El patrón Observer está implementado usando Kafka Topics. Los servicios se suscriben (escuchan) a eventos publicados por otros servicios sin acoplamiento directo.

### Código de Ejemplo
```java
// circleguard-promotion-service/src/main/java/com/circleguard/promotion/listener/SurveyListener.java
@Component
@RequiredArgsConstructor
@Slf4j
public class SurveyListener {
    private final HealthStatusService healthStatusService;

    @KafkaListener(topics = "survey.submitted", groupId = "promotion-service-group")
    public void onSurveySubmitted(Map<String, Object> event) {
        log.info("Received survey submission event");
        String anonymousId = (String) event.get("anonymousId");
        Boolean hasSymptoms = (Boolean) event.get("hasSymptoms");

        if (anonymousId != null && Boolean.TRUE.equals(hasSymptoms)) {
            healthStatusService.updateStatus(anonymousId, "SUSPECT");
        }
    }
}

// circleguard-notification-service/src/main/java/com/circleguard/notification/service/ExposureNotificationListener.java
@Component
@RequiredArgsConstructor
public class ExposureNotificationListener {

    @KafkaListener(topics = "promotion.status.changed", groupId = "notification-group")
    public void onStatusChanged(Map<String, Object> event) {
        // Procesa el evento y envía notificación al usuario
    }
}
```

### Beneficio Obtenido
- Desacoplamiento total entre servicios productores y consumidores
- Comunicación asíncrona y escalable
- Fácil agregar nuevos observadores sin modificar productores
- Auditoría y replay de eventos mediante Kafka

---

## 4. Decorator Pattern

### Ubicación
- **Proyecto:** circle-guard-development
- **Servicio:** circleguard-auth-service
- **Clase:** `com.circleguard.auth.security.JwtAuthenticationFilter.java`

### Descripción
El Decorator Pattern se implementa mediante Servlet Filters que decoran las request HTTP, agregando funcionalidad de validación de JWT sin modificar el controlador original.

### Código de Ejemplo
```java
// circleguard-auth-service/src/main/java/com/circleguard/auth/security/JwtAuthenticationFilter.java
@Component
public class JwtAuthenticationFilter extends OncePerRequestFilter {

    private final Key key;

    public JwtAuthenticationFilter(@Value("${jwt.secret}") String secret) {
        this.key = Keys.hmacShaKeyFor(secret.getBytes());
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain filterChain)
            throws ServletException, IOException {
        String header = request.getHeader("Authorization");

        if (header != null && header.startsWith("Bearer ")) {
            String token = header.substring(7);
            try {
                Claims claims = Jwts.parserBuilder()
                        .setSigningKey(key)
                        .build()
                        .parseClaimsJws(token)
                        .getBody();

                // Decora la request con información de autenticación
                UsernamePasswordAuthenticationToken auth =
                    new UsernamePasswordAuthenticationToken(
                        claims.getSubject(),
                        null,
                        extractAuthorities(claims)
                    );
                SecurityContextHolder.getContext().setAuthentication(auth);
            } catch (Exception e) {
                SecurityContextHolder.clearContext();
            }
        }

        filterChain.doFilter(request, response);
    }
}
```

### Beneficio Obtenido
- Validación de JWT transparente en todas las requests
- Separación de intereses entre autenticación y lógica de negocio
- Reutilizable en múltiples controladores
- Fácil de testear de forma aislada

---

## 5. Circuit Breaker Pattern

### Ubicación
- **Proyecto:** circle-guard-operation
- **Manifests:** `istio/destination-rules.yml`
- **Nivel:** Infraestructura (Istio service mesh)

### Descripción
El Circuit Breaker es implementado a nivel de infraestructura mediante Istio DestinationRules, monitoreando la salud de los servicios y cortando el circuito si hay demasiadas fallas.

### Código de Ejemplo
```yaml
# istio/destination-rules.yml
---
# Circuit Breaker para identity-service
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: identity-service-cb
  namespace: circleguard-prod
spec:
  host: identity-service
  trafficPolicy:
    outlierDetection:
      consecutive5xxErrors: 5        # Aislar después de 5 errores 5xx
      interval: 30s                  # Revisar cada 30 segundos
      baseEjectionTime: 30s          # Mantener aislado 30 segundos
      maxEjectionPercent: 50         # No aislar más del 50% de instancias
    connectionPool:
      http:
        http1MaxPendingRequests: 100
        http2MaxRequests: 1000
        idleTimeout: 90s
```

### Beneficio Obtenido
- Previene cascadas de fallos entre servicios
- Recuperación automática cuando el servicio se estabiliza
- Monitoreo transparente sin modificar código de aplicación
- Límites de conexión para evitar saturación

---

## 6. External Configuration Pattern

### Ubicación
- **Proyecto:** circle-guard-operation
- **Manifests:** `k8s/configmaps/configmap-infra.yml`
- **Nivel:** Kubernetes ConfigMaps

### Descripción
La configuración externa se gestiona mediante Kubernetes ConfigMaps, permitiendo diferentes configuraciones por ambiente (dev, staging, prod) sin recompilar la aplicación.

### Código de Ejemplo
```yaml
# k8s/configmaps/configmap-infra.yml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: circleguard-infra-config
  namespace: circleguard-prod
data:
  # Base de datos
  POSTGRES_HOST: "circleguard-postgres.circleguard-prod.svc.cluster.local"
  POSTGRES_PORT: "5432"
  POSTGRES_USER: "admin"

  # Message Broker
  KAFKA_BOOTSTRAP_SERVERS: "circleguard-kafka.circleguard-prod.svc.cluster.local:9092"
  KAFKA_BROKERS: "circleguard-kafka.circleguard-prod.svc.cluster.local:9092"

  # Cache distribuido
  REDIS_HOST: "circleguard-redis.circleguard-prod.svc.cluster.local"
  REDIS_PORT: "6379"

  # Base de datos de grafos
  NEO4J_URI: "bolt://circleguard-neo4j.circleguard-prod.svc.cluster.local:7687"
  NEO4J_USERNAME: "neo4j"

  # Directorio LDAP
  LDAP_URL: "ldap://circleguard-openldap.circleguard-prod.svc.cluster.local:389"
  LDAP_BASE_DN: "dc=circleguard,dc=edu"
  LDAP_MANAGER_DN: "cn=admin,dc=circleguard,dc=edu"

  # Logging
  LOGGING_LEVEL_ROOT: "WARN"
  LOGGING_LEVEL_COM_CIRCLEGUARD: "INFO"

  # Actuator endpoints
  MANAGEMENT_ENDPOINTS_WEB_EXPOSURE_INCLUDE: "health,info,metrics,prometheus"
```

### Beneficio Obtenido
- Misma imagen de contenedor para todos los ambientes
- Configuración específica por ambiente sin necesidad de recompilación
- Facilita la replicación y portabilidad de la plataforma
- Separación clara entre configuración de infraestructura y código

---

## 7. Saga Choreography Pattern

### Ubicación
- **Proyecto:** circle-guard-development
- **Flujo:** form-service → Kafka → promotion-service → Kafka → notification-service
- **Clases relevantes:**
  - `circleguard-form-service/src/main/java/com/circleguard/form/service/HealthSurveyService.java`
  - `circleguard-promotion-service/src/main/java/com/circleguard/promotion/listener/SurveyListener.java`
  - `circleguard-promotion-service/src/main/java/com/circleguard/promotion/service/HealthStatusService.java`
  - `circleguard-notification-service/src/main/java/com/circleguard/notification/service/ExposureNotificationListener.java`

### Descripción
El patrón Saga Choreography orquesta transacciones distribuidas usando eventos de Kafka. Cada servicio participa en la saga reaccionando a eventos y publicando nuevos eventos, sin coordinador central.

### Flujo de Eventos

```
1. Formulario Enviado (form-service)
   ├─ Evento: "survey.submitted"
   ├─ Datos: {anonymousId, hasSymptoms, timestamp}
   └─ Publica a Kafka

2. Verificar Síntomas (promotion-service)
   ├─ Escucha: "survey.submitted"
   ├─ Actualiza estado: ACTIVE → SUSPECT
   ├─ Evento: "promotion.status.changed"
   └─ Publica a Kafka

3. Enviar Notificaciones (notification-service)
   ├─ Escucha: "promotion.status.changed", "alert.priority", "circle.fenced"
   ├─ Envía notificaciones a usuarios
   └─ Registra auditoría
```

### Código de Ejemplo

**Paso 1: form-service publica evento**
```java
// circleguard-form-service/src/main/java/com/circleguard/form/service/HealthSurveyService.java
@Service
@RequiredArgsConstructor
public class HealthSurveyService {
    private final HealthSurveyRepository repository;
    private final KafkaTemplate<String, Object> kafkaTemplate;
    private static final String TOPIC_SURVEY_SUBMITTED = "survey.submitted";

    @Transactional
    public HealthSurvey submitSurvey(HealthSurvey survey) {
        boolean hasSymptoms = checkSymptoms(survey);

        HealthSurvey saved = repository.save(survey);

        // Publica evento para iniciar la saga
        Map<String, Object> event = Map.of(
            "anonymousId", saved.getAnonymousId(),
            "hasSymptoms", hasSymptoms,
            "timestamp", System.currentTimeMillis()
        );
        kafkaTemplate.send(TOPIC_SURVEY_SUBMITTED, saved.getAnonymousId().toString(), event);

        return saved;
    }
}
```

**Paso 2: promotion-service consume y publica nuevo evento**
```java
// circleguard-promotion-service/src/main/java/com/circleguard/promotion/listener/SurveyListener.java
@Component
@RequiredArgsConstructor
public class SurveyListener {
    private final HealthStatusService healthStatusService;

    @KafkaListener(topics = "survey.submitted", groupId = "promotion-service-group")
    public void onSurveySubmitted(Map<String, Object> event) {
        String anonymousId = (String) event.get("anonymousId");
        Boolean hasSymptoms = (Boolean) event.get("hasSymptoms");

        if (Boolean.TRUE.equals(hasSymptoms)) {
            // Actualiza estado y publica nuevo evento
            healthStatusService.updateStatus(anonymousId, "SUSPECT");
        }
    }
}

// circleguard-promotion-service/src/main/java/com/circleguard/promotion/service/HealthStatusService.java
@Service
@RequiredArgsConstructor
public class HealthStatusService {
    private final KafkaTemplate<String, Object> kafkaTemplate;
    private static final String TOPIC_STATUS_CHANGED = "promotion.status.changed";

    public void updateStatus(String anonymousId, String status) {
        // Actualiza estado en Neo4j y Redis
        updateInGraphAndCache(anonymousId, status);

        // Publica evento para siguiente paso de la saga
        Map<String, Object> payload = Map.of(
            "anonymousId", anonymousId,
            "newStatus", status,
            "timestamp", System.currentTimeMillis()
        );
        kafkaTemplate.send(TOPIC_STATUS_CHANGED, anonymousId, payload);
    }
}
```

**Paso 3: notification-service consume y realiza acciones finales**
```java
// circleguard-notification-service/src/main/java/com/circleguard/notification/service/ExposureNotificationListener.java
@Component
@RequiredArgsConstructor
public class ExposureNotificationListener {
    private final NotificationService notificationService;

    @KafkaListener(topics = "promotion.status.changed", groupId = "notification-group")
    public void onStatusChanged(Map<String, Object> event) {
        String anonymousId = (String) event.get("anonymousId");
        String newStatus = (String) event.get("newStatus");

        if ("SUSPECT".equals(newStatus)) {
            // Envía notificación al usuario
            notificationService.sendSuspectNotification(anonymousId);

            // Notifica a contactos cercanos
            notificationService.notifyCloseContacts(anonymousId);
        }
    }
}
```

### Beneficio Obtenido
- **Sin punto de fallo central:** No hay orquestador que pueda fallar
- **Escalabilidad:** Cada servicio escala independientemente
- **Resilencia:** Si un servicio falla, la saga se detiene pero los datos se preservan
- **Auditoría:** Todos los pasos quedan registrados en Kafka
- **Desacoplamiento:** Los servicios no conocen la implementación unos de otros
- **Flexibilidad:** Fácil agregar nuevos pasos o listeners a la saga

---

## Conclusión

La arquitectura de CircleGuard implementa patrones de diseño reconocidos que proporcionan:

- **Modularidad:** Separación clara de responsabilidades
- **Escalabilidad:** Capacidad de crecer horizontal y verticalmente
- **Resiliencia:** Tolerancia a fallos mediante Circuit Breakers y Sagas
- **Mantenibilidad:** Código limpio y fácil de entender
- **Flexibilidad:** Facilidad para agregar nuevas características

Estos patrones trabajan en conjunto para crear una arquitectura de microservicios robusta y confiable.
