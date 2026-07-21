#!/bin/sh

RESOURCE_GROUP="${1:-}"
LOCATION="${2:-}"
ARTIFACTS_LOCATION="${3:-}"
NODE_COUNT="${4:-}"

if [ -z "$RESOURCE_GROUP" ] || [ -z "$LOCATION" ]; then
  echo "Usage: ./deploy.sh <resource-group> <location> [artifacts-location] [node-count]"
  exit 1
fi

az group create --name $RESOURCE_GROUP --location $LOCATION
set -- \
  --template-file mainTemplate.json \
  --resource-group $RESOURCE_GROUP \
  --parameters @mainTemplateParameters.json

if [ -n "$ARTIFACTS_LOCATION" ]; then
  ARTIFACTS_LOCATION="${ARTIFACTS_LOCATION%/}/"
  set -- "$@" --parameters _artifactsLocation="$ARTIFACTS_LOCATION"
fi

if [ -n "$NODE_COUNT" ]; then
  set -- "$@" --parameters nodeCount="$NODE_COUNT"
fi

az deployment group create "$@"
