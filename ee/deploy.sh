#!/bin/sh

RESOURCE_GROUP="${1:-}"
LOCATION="${2:-}"
ARTIFACTS_LOCATION="${3:-https://raw.githubusercontent.com/neo4j-partners/azure-resource-manager-neo4j/refs/heads/main/ee/}"

if [ -z "$RESOURCE_GROUP" ] || [ -z "$LOCATION" ]; then
  echo "Usage: ./deploy.sh <resource-group> <location> [artifacts-location]"
  exit 1
fi

az group create --name $RESOURCE_GROUP --location $LOCATION
az deployment group create \
  --template-file mainTemplate.json \
  --resource-group $RESOURCE_GROUP \
  --parameters @mainTemplateParameters.json \
  --parameters _artifactsLocation="$ARTIFACTS_LOCATION"
