#!/usr/bin/env bash
# setup-sealed-secrets.sh
# Genera SealedSecrets para cada ambiente usando kubeseal.
# Requiere: kubeseal CLI instalado, kubectl configurado al cluster correcto.
#
# Uso:
#   ./scripts/setup-sealed-secrets.sh dev     # para circleguard-dev
#   ./scripts/setup-sealed-secrets.sh staging # para circleguard-stage
#   ./scripts/setup-sealed-secrets.sh prod    # para circleguard-prod

set -euo pipefail

ENV=${1:-""}
if [[ -z "$ENV" ]]; then
  echo "Usage: $0 <dev|staging|prod>"
  exit 1
fi

case "$ENV" in
  dev)     NAMESPACE="circleguard-dev";   OUTPUT="k8s/secrets/sealed-secret-dev.yml" ;;
  staging) NAMESPACE="circleguard-stage"; OUTPUT="k8s/secrets/sealed-secret-stage.yml" ;;
  prod)    NAMESPACE="circleguard-prod";  OUTPUT="k8s/secrets/sealed-secret-prod.yml" ;;
  *)
    echo "Unknown environment: $ENV. Use dev, staging, or prod."
    exit 1
    ;;
esac

echo "Generating SealedSecret for namespace: $NAMESPACE"
echo "Output file: $OUTPUT"
echo ""
echo "You will be prompted to enter secret values. These are never stored in plain text."
echo ""

read -rsp "POSTGRES_PASSWORD: " POSTGRES_PASSWORD; echo
read -rsp "NEO4J_PASSWORD: " NEO4J_PASSWORD; echo
read -rsp "JWT_SECRET (min 32 chars): " JWT_SECRET; echo
read -rsp "QR_SECRET: " QR_SECRET; echo
read -rsp "VAULT_SECRET: " VAULT_SECRET; echo
read -rsp "VAULT_SALT: " VAULT_SALT; echo
read -rsp "VAULT_HASH_SALT: " VAULT_HASH_SALT; echo
read -rsp "LDAP_MANAGER_PASSWORD: " LDAP_MANAGER_PASSWORD; echo

kubectl create secret generic circleguard-secret \
  --namespace="$NAMESPACE" \
  --from-literal=POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
  --from-literal=NEO4J_PASSWORD="$NEO4J_PASSWORD" \
  --from-literal=JWT_SECRET="$JWT_SECRET" \
  --from-literal=QR_SECRET="$QR_SECRET" \
  --from-literal=VAULT_SECRET="$VAULT_SECRET" \
  --from-literal=VAULT_SALT="$VAULT_SALT" \
  --from-literal=VAULT_HASH_SALT="$VAULT_HASH_SALT" \
  --from-literal=LDAP_MANAGER_PASSWORD="$LDAP_MANAGER_PASSWORD" \
  --dry-run=client -o yaml | \
kubeseal \
  --controller-name=sealed-secrets \
  --controller-namespace=kube-system \
  --format yaml > "$OUTPUT"

echo ""
echo "SealedSecret written to: $OUTPUT"
echo "This file is safe to commit to git."
