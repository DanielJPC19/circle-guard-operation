#!/bin/bash
# Usage: ./scripts/update-image-tag.sh <service> <new-tag> <environment>
# Example: ./scripts/update-image-tag.sh auth-service v1.42 prod

set -e

SERVICE=$1
TAG=$2
ENV=$3

if [ -z "$SERVICE" ] || [ -z "$TAG" ] || [ -z "$ENV" ]; then
    echo "Usage: $0 <service> <tag> <environment>"
    echo "  environment: dev | staging | prod"
    exit 1
fi

# Map environment names: staging → stage, dev → dev, prod → prod
case "$ENV" in
    dev)
        K8S_ENV="dev"
        ;;
    staging)
        K8S_ENV="stage"
        ;;
    prod)
        K8S_ENV="prod"
        ;;
    *)
        echo "Error: Unknown environment '$ENV'. Valid: dev, staging, prod"
        exit 1
        ;;
esac

MANIFEST="k8s/services/${K8S_ENV}/all-services.yml"

if [ ! -f "$MANIFEST" ]; then
    echo "Error: manifest not found at $MANIFEST"
    exit 1
fi

ACR_REGISTRY="cgregicesi.azurecr.io"
IMAGE_PATTERN="${ACR_REGISTRY}/circleguard/circleguard-${SERVICE}"

sed -i "s|image: ${IMAGE_PATTERN}:.*|image: ${IMAGE_PATTERN}:${TAG}|g" "$MANIFEST"

echo "Updated $MANIFEST -> ${IMAGE_PATTERN}:${TAG}"
