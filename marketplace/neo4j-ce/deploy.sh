#!/bin/bash
set -euo pipefail

# Deploy Neo4j Community Edition to Azure
# Usage: ./deploy.sh <resource-group-name> [region]

RESOURCE_GROUP="${1:?Usage: ./deploy.sh <resource-group-name> [region]}"
REGION="${2:-eastus2}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Read password from parameters.json
ADMIN_PASSWORD=$(jq -r '.adminPassword.value' "${SCRIPT_DIR}/parameters.json")
if [ -z "${ADMIN_PASSWORD}" ] || [ "${ADMIN_PASSWORD}" = "null" ]; then
  echo "ERROR: adminPassword is empty or missing in parameters.json"
  exit 1
fi

echo "=== Neo4j Community Edition Deployment ==="
echo "Resource Group: ${RESOURCE_GROUP}"
echo "Region: ${REGION}"
echo ""

# Create resource group
echo "Creating resource group..."
az group create --name "${RESOURCE_GROUP}" --location "${REGION}"

# Compile Bicep to ARM JSON
echo "Compiling Bicep template..."
az bicep build --file "${SCRIPT_DIR}/main.bicep" --outfile "${SCRIPT_DIR}/mainTemplate-generated.json"

# Deploy with password passed as a secure parameter override
echo "Deploying Neo4j Community Edition..."
az deployment group create \
  --resource-group "${RESOURCE_GROUP}" \
  --template-file "${SCRIPT_DIR}/mainTemplate-generated.json" \
  --parameters "${SCRIPT_DIR}/parameters.json" \
  --parameters adminPassword="${ADMIN_PASSWORD}" \
  --output json

# Clean up generated JSON
rm -f "${SCRIPT_DIR}/mainTemplate-generated.json"

echo ""
echo "=== Deployment complete ==="
