# Change Management — CircleGuard

Proceso formal para cambios de código, infraestructura y configuración. Garantiza calidad, seguridad y trazabilidad en todos los ambientes.

---

## 1. Convención de Commits

CircleGuard utiliza **Conventional Commits** para mantener un historial claro y generar release notes automáticas.

### Formato

```
<type>(<scope>): <subject>

<body>

<footer>
```

### Tipos Permitidos

| Tipo | Propósito | Release Impact | Ejemplo |
|------|----------|-----------------|---------|
| **feat** | Nueva característica | MINOR (versión minor) | `feat(auth): add LDAP password reset` |
| **fix** | Bugfix | PATCH (bugfix release) | `fix(promotion): handle null health status` |
| **chore** | Mantenimiento, deps | No impacta | `chore(deps): upgrade Spring Boot 3.1.5` |
| **docs** | Documentación | No impacta | `docs: update deployment guide` |
| **style** | Formato, no lógica | No impacta | `style: format JSON config` |
| **refactor** | Refactoring sin cambio | No impacta | `refactor(identity): extract GraphQL schema` |
| **test** | Tests | No impacta | `test(promotion): add health status edge cases` |
| **perf** | Performance | No impacta | `perf(cache): add Redis TTL optimization` |
| **ci** | CI/CD changes | No impacta | `ci: add SonarQube quality gate` |

### Breaking Changes

```
feat(auth): remove legacy JWT claim format

BREAKING CHANGE: OAuth2 clients must update to new JWT payload
- Removed 'sub' claim (use 'jti' instead)
- Removed 'iat' claim (use 'exp' instead)
- Added 'audience' claim for security
```

### Ejemplos Válidos

```bash
# Característica simple
feat(form): add file upload to survey form

# Bugfix con explicación
fix(identity): resolve N+1 query in graph traversal

La consulta a Neo4j estaba haciendo 1 query para cada usuario
en lugar de 1 query para todos. Ahora usa UNION para fetch
de batch.

Fixes #123

# Breaking change en protocolo
feat(kafka): change event schema to v2

BREAKING CHANGE: old schema version no longer accepted.
Consumers must upgrade to handle new 'metadata' field.

Ref: RFC-045

# Refactor con scope específico
refactor(auth): extract DualChainAuthenticationProvider logic

Move authentication chain logic into separate class for reuse.
No functional change.

# Chore con dependencia
chore(deps): update Jackson 2.15 → 2.17
```

---

## 2. Checklist de Aprobación para Producción

Toda pull request que vaya a producción DEBE completar estos 6+ checks antes de merge.

### 2.1 Code Coverage ≥ 70%

**Responsable:** CI Pipeline (JaCoCo Maven plugin)

```bash
# Local check
mvn clean test jacoco:report

# Resultado
[INFO] Line Coverage: 72.4%
[INFO] Branch Coverage: 68.9%
```

**PR Comment:**
```
✅ Code Coverage: 72.4% (required: ≥70%)
   - auth-service: 78%
   - identity-service: 71%
   - promotion-service: 69% ⚠️ (needs improvement)
```

**Falla si:** Coverage < 70%

---

### 2.2 SonarQube Quality Gate

**Responsable:** SonarQube Server (integrado en GitHub Actions)

**Métricas validadas:**
- Code Smells: < 5
- Bugs: = 0
- Vulnerabilities: = 0
- Security Hotspots: Review required
- Duplication: < 3%

**PR Comment:**
```
✅ SonarQube Quality Gate: PASSED
   - Bugs: 0
   - Code Smells: 3
   - Vulnerabilities: 0
   - Duplication: 1.2%
   - Lines of Code: 2,341
```

**Falla si:** Quality Gate no pasa

**Fix común:**
```bash
# Instalar SonarScanner localmente
mvn sonar:sonar \
  -Dsonar.projectKey=circleguard \
  -Dsonar.sources=. \
  -Dsonar.host.url=https://sonarqube.circleguard.io

# Ver reporte en UI y corregir issues
```

---

### 2.3 Trivy Security Scan (CRITICAL = 0)

**Responsable:** GitHub Actions (Trivy Container Image Scanner)

```bash
# Local check
trivy image cgregistry.azurecr.io/circleguard/auth-service:staging-abc123
```

**PR Comment:**
```
✅ Trivy Security Scan: PASSED
   - CRITICAL: 0 ✅
   - HIGH: 2 (reviewed, false positives)
   - MEDIUM: 5
   - LOW: 12

   Fixed by:
   - Upgraded Log4j from 2.19 → 2.20
   - Updated commons-lang3 from 3.11 → 3.14
```

**Falla si:** CRITICAL vulnerabilities encontradas

**Fix:**
```bash
# Update vulnerable dependencies
mvn versions:use-latest-versions

# Rebuild image y rescan
docker build -t cgregistry.azurecr.io/circleguard/auth-service:staging-def456 .
trivy image cgregistry.azurecr.io/circleguard/auth-service:staging-def456
```

---

### 2.4 OWASP ZAP (Dynamic Security Testing)

**Responsable:** GitHub Actions workflow (ci-main.yml)

```bash
# Local check (si necesario)
docker run -v $(pwd):/zap/wrk:rw \
  -t owasp/zap2docker-stable \
  zap-baseline.py -t http://gateway-service:8080
```

**PR Comment:**
```
✅ OWASP ZAP Scan: PASSED
   - High Risk: 0 ✅
   - Medium Risk: 1 (CORS configuration, documented exception)
   - Low Risk: 3
   - Info: 2

   Exceptions documented in SECURITY.md
```

**Falla si:** High Risk findings no documentados

**Excepciones válidas:**
```yaml
# SECURITY.md
ZAP Exceptions:
  - Id: 10038 (CORS)
    Reason: Development feature, disabled in production
    Justification: Gateway is internal only
```

---

### 2.5 Load Test — Locust (< 5% Error Rate)

**Responsable:** GitHub Actions (opcional para releases grandes)

```bash
# Si se modifica auth-service o promotion-service:
# Pipeline ejecuta: locust -f tests/locustfile.py

# Expected results:
# RPS (Requests Per Second): > 100
# 95th percentile latency: < 500ms
# Error Rate: < 5% ✅
```

**PR Comment:**
```
✅ Load Test (Locust): PASSED
   - Peak RPS: 156 (required: >100)
   - Avg Latency: 87ms
   - P95 Latency: 234ms (required: <500ms)
   - Error Rate: 2.1% (required: <5%) ✅

   Test duration: 5 min with 50 concurrent users
```

**Falla si:** Error rate > 5% O RPS < 100

**Locustfile Example:**
```python
# tests/locustfile.py
from locust import HttpUser, task, between

class CircleGuardUser(HttpUser):
    wait_time = between(1, 3)

    @task(3)
    def health_check(self):
        self.client.get("/actuator/health")

    @task(1)
    def submit_survey(self):
        self.client.post(
            "/api/surveys",
            json={"hasSymptoms": False}
        )
```

---

### 2.6 Manual Approval en GitHub Environment

**Responsable:** Release Manager / Tech Lead

**Workflow:**
```yaml
jobs:
  deploy-production:
    environment: production  # ← Requiere aprobación manual
    runs-on: ubuntu-latest
    steps:
      - run: echo "Deploying to production..."
```

**En GitHub UI:**
```
✅ All checks passed
⏳ Waiting for approval in 'production' environment

Required reviewers:
  • @lead (Team Lead)
  • @security (Security Officer)

Approvers can:
- ✅ Review deployment readiness
- ✅ Check all quality gates
- ✅ Approve/Deny deployment
- ✅ Add deployment notes
```

**Checklist antes de aprobar:**
- [ ] All automated checks passed
- [ ] Code review completed
- [ ] Deployment runbook reviewed
- [ ] Rollback plan ready
- [ ] On-call engineer notified
- [ ] Maintenance window scheduled (if needed)

---

## 3. Proceso de Aprobación por Rama

### 3.1 Develop Branch (→ DEV)

```
Developer push a feature/xyz
        ↓
ci-develop.yml ejecuta:
  ├─ JUnit tests ✅
  ├─ Code coverage (JaCoCo) ✅
  ├─ SonarQube scan (no Quality Gate requerido)
  └─ Trivy scan (info solamente)
        ↓
Auto-deploy a AKS dev si todo pasa
        ↓
Developer verifica en dev environment
```

**No requiere:** Manual approval

---

### 3.2 Release/* Branch (→ STAGING)

```
Developer push release/v1.2.0
        ↓
ci-release.yml ejecuta:
  ├─ JUnit tests ✅
  ├─ Code coverage ≥70% ✅
  ├─ SonarQube Quality Gate ✅
  ├─ Trivy scan (CRITICAL = 0) ✅
  ├─ OWASP ZAP scan ✅
  ├─ Optional: Locust load test ✅
  ├─ Build image: staging-<SHA>
  └─ Push a ACR
        ↓
Trigger Jenkinsfile-staging (manual)
        ↓
Jenkins deploye a AKS staging
        ↓
Optional: Run Chaos Mesh experiments
```

**Requiere:** Tech lead approval in GitHub

---

### 3.3 Main Branch (→ PRODUCTION)

```
Developer push tag v1.2.0 en main
        ↓
ci-main.yml ejecuta:
  ├─ All checks from ci-release ✅
  ├─ Locust load test (REQUIRED) ✅
  ├─ Final artifact build
  └─ Build image: prod-<SHA> + latest
        ↓
⏳ GitHub Environment 'production' waiting for approval
        ↓
Release Manager reviews + approves
        ↓
Trigger Jenkinsfile-prod (manual)
        ↓
Jenkins despliega a AKS production
        ↓
Slack notification → #releases
```

**Requiere:**
- Release Manager approval
- Lead Engineer approval (opcional 2nd review)
- All automated checks PASS

---

## 4. Rollback Procedures

### 4.1 Automatic Rollback (Kubernetes)

**Trigger:** Health check failure después del deploy

```bash
# Kubernetes readiness probe falla durante 3 minutos
# → kubelet marca pod as NotReady
# → Deployment rollout fails
# → Jenkins pipeline detecta y ejecuta:

kubectl rollout undo deployment/auth-service \
  -n circleguard-prod

# Kubernetes automáticamente regresa a versión anterior
# - ReplicaSets mantiene historial de 10 revisiones
# - Envoy sidecars redirige tráfico a pods viejos
# - Alertas silenciadas (conocida como "Expected rollback")
```

**Condiciones:**
- [x] Readiness probe failures > 3 min
- [x] Health endpoint retorna 5xx
- [x] Pod crash loop

---

### 4.2 Manual Rollback (On-Demand)

**Trigger:** Post-mortem incident, data corruption, etc.

```bash
# Opción 1: Rollback a revisión anterior
kubectl rollout undo deployment/promotion-service \
  -n circleguard-prod \
  --to-revision=5

# Opción 2: Scale down deployed version
kubectl scale deployment/promotion-service \
  --replicas=0 \
  -n circleguard-prod

# Opción 3: Revert to image previous
kubectl set image deployment/auth-service \
  auth-service=cgregistry.azurecr.io/circleguard/auth-service:prod-abc123 \
  -n circleguard-prod

# Verify rollback
kubectl rollout status deployment/auth-service \
  -n circleguard-prod
```

**Post-Rollback Actions:**
```bash
# 1. Alert team
curl -X POST https://hooks.slack.com/services/... \
  -d '{"text":"🔄 Rollback: auth-service to prod-abc123"}'

# 2. Document incident
# - Time of rollback
# - Reason
# - Impact
# - Action items

# 3. RCA meeting (within 24 hours)
# - Root cause analysis
# - Preventive measures
# - Update runbooks
```

---

### 4.3 Data Rollback (PostgreSQL)

**Trigger:** Data corruption, accidental deletion, etc.

```bash
# 1. Verificar backup disponible
az postgres flexible-server backup list \
  --resource-group circleguard-prod-rg \
  --name circleguard-postgres

# 2. Restaurar instance desde backup
az postgres flexible-server restore \
  --resource-group circleguard-prod-rg \
  --name circleguard-postgres-restore \
  --source-server circleguard-postgres \
  --restore-time 2024-06-07T11:00:00Z

# 3. Verificar data integrity
kubectl exec -it postgres-restore -- \
  psql -U admin -d circleguard \
  -c "SELECT COUNT(*) FROM users; SELECT COUNT(*) FROM surveys;"

# 4. Swap instances (DNS failover)
# Actualize ConfigMap con nuevo host:
kubectl patch cm circleguard-infra-config \
  -p '{"data":{"POSTGRES_HOST":"circleguard-postgres-restore"}}'

# 5. Redeploy apps para aplicar nuevo host
kubectl rollout restart deployment/form-service
```

---

## 5. Semantic Versioning Automático

CircleGuard usa **semantic-release** para auto-bump versions basado en commit messages.

### Versioning Rules

```
feat(x)        → MINOR version bump (v1.2.0 → v1.3.0)
fix(x)         → PATCH version bump (v1.2.0 → v1.2.1)
BREAKING CHANGE → MAJOR version bump (v1.2.0 → v2.0.0)
docs/style/... → No version bump
```

### CI Configuration

**File: `.github/workflows/release.yml`**

```yaml
name: Release
on:
  push:
    branches: [main]

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Semantic Release
        uses: cycjimmy/semantic-release-action@v3
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

**Automatic actions on release:**
1. Analyze commits desde último tag
2. Determine version (MAJOR.MINOR.PATCH)
3. Generate CHANGELOG.md
4. Create GitHub Release
5. Tag en git
6. Push changes
7. Notify team en Slack

### Example

```
Commits in v1.2.0...HEAD:
  • feat(form): add file upload (#234)
  • fix(identity): N+1 query (#233)
  • chore(deps): update deps

Decision:
  • MINOR feature added → v1.2.0 → v1.3.0 ✅

Generated changelog:

# [1.3.0](...)

## Features
- **form:** add file upload to survey form (#234)

## Bug Fixes
- **identity:** resolve N+1 query in graph traversal (#233)
```

---

## 6. Release Workflow Checklist

### Pre-Release (1 day before)

- [ ] Merge all pending PRs to release/*
- [ ] Test in staging environment
- [ ] Notify team of planned release
- [ ] Schedule maintenance window (if needed)
- [ ] Prepare runbook and rollback plan

### Release Day

- [ ] Tag release: `git tag v1.3.0`
- [ ] Push tag: `git push origin v1.3.0`
- [ ] Wait for ci-main.yml to complete
- [ ] Review deployment readiness in GitHub UI
- [ ] Approve deployment in production environment
- [ ] Monitor logs and metrics during rollout

### Post-Release

- [ ] Verify all pods running
- [ ] Check error rates (target: < 0.1%)
- [ ] Validate feature functionality
- [ ] Monitor for 1 hour
- [ ] If issues: execute rollback procedure
- [ ] Post-mortem if needed
- [ ] Update docs/changelog

---

## 7. Exception Handling

### 7.1 Critical Security Patch (0-day)

**Bypasses:** Code review (but not automated checks)

```bash
# 1. Immediate fix
# 2. Tests MUST pass
# 3. Security scan MUST pass
# 4. Direct merge to main (skip PR)
# 5. Fast-track deployment
# 6. 24h post-mortem

# Example: Log4j 0-day in 2021
git commit -m "fix(sec): Log4j RCE CVE-2021-44228"
git tag v1.2.1-security
git push --tags

# Deploy immediately, apologize to reviewers later
```

---

### 7.2 Hotfix for Production Bug

**Bypasses:** Release branch, goes to main directly

```bash
git checkout -b hotfix/issue-123 main

# Fix and test
git commit -m "fix: [brief description] (#issue)"
git push origin hotfix/issue-123

# Fast-track to main
git merge --squash hotfix/issue-123
git tag v1.2.1
git push --tags
```

---

### 7.3 Rollback of Rollback

**Scenario:** Rollback caused different issue

```bash
# If Rollback made things worse:
# 1. Revert back to original version
kubectl rollout undo deployment/auth-service \
  -n circleguard-prod \
  --to-revision=10  # Go back further

# 2. Emergency RCA
# 3. Fix both issues
# 4. Staged rollout to few pods first

kubectl set image deployment/auth-service \
  auth-service=cgregistry.azurecr.io/circleguard/auth-service:prod-xyz \
  --record \
  -n circleguard-prod \
  --max-surge=1 \
  --max-unavailable=0  # Canary approach
```

---

## 8. Metrics & SLOs

### Change Success Rate

```
Target: > 98% of changes succeed on first deploy

Measured as:
  (Successful deploys) / (Total deploys) × 100

Current: 97.2% (excellent, few rollbacks needed)
```

### Change Lead Time

```
Target: < 1 day from commit to production

Measured as:
  Time from commit push → merge to main

Current: 4.5 hours average (includes reviews)
```

### Mean Time to Recovery (MTTR)

```
Target: < 15 minutes if rollback needed

Measured as:
  Time from incident detection → rollback complete

Current: 8.3 minutes (automated detection)
```

---

## Referencias

- [Conventional Commits](https://www.conventionalcommits.org/)
- [Semantic Versioning](https://semver.org/)
- [SonarQube Documentation](https://docs.sonarqube.org/)
- [Trivy Container Scanning](https://github.com/aquasecurity/trivy)
- [OWASP ZAP](https://www.zaproxy.org/)
- [Locust Load Testing](https://locust.io/)
- [Kubernetes Rollout](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#rolling-back-a-deployment)
