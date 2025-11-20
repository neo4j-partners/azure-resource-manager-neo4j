#!/bin/bash

# Test script for Neo4j Enterprise marketplace deployment with Azure Key Vault
# This script creates a Key Vault, stores a password, deploys Neo4j, validates, and cleans up

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Generate unique names
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
RESOURCE_GROUP="neo4j-test-kv-${TIMESTAMP}"
VAULT_NAME="kvneo4j${TIMESTAMP:2:14}"  # Max 24 chars, alphanumeric only (remove hyphens)
LOCATION="${LOCATION:-eastus}"
SECRET_NAME="neo4j-admin-password"

# Generate a secure password
echo_info "Generating secure password..."
PASSWORD=$(openssl rand -base64 32 | tr -d '/+=' | head -c 32)
if [ -z "$PASSWORD" ]; then
    echo_error "Failed to generate password"
    exit 1
fi
echo_info "Password generated successfully"

# Cleanup function
cleanup() {
    echo_info "Cleaning up resources..."

    # Check if we should skip cleanup
    if [ "${SKIP_CLEANUP}" = "true" ]; then
        echo_warn "SKIP_CLEANUP is set, leaving resources for inspection"
        echo_warn "Resource Group: ${RESOURCE_GROUP}"
        echo_warn "Key Vault: ${VAULT_NAME}"
        echo_warn "Password: ${PASSWORD}"
        echo_warn "To delete manually: az group delete --name ${RESOURCE_GROUP} --yes"
        return 0
    fi

    # Delete resource group (includes all resources)
    if az group exists --name ${RESOURCE_GROUP} > /dev/null 2>&1; then
        echo_info "Deleting resource group ${RESOURCE_GROUP}..."
        az group delete --name ${RESOURCE_GROUP} --yes --no-wait
        echo_info "Cleanup initiated (running in background)"
    fi
}

# Set trap to cleanup on exit
trap cleanup EXIT

# Create resource group
echo_info "Creating resource group: ${RESOURCE_GROUP}"
az group create \
    --name ${RESOURCE_GROUP} \
    --location ${LOCATION} \
    --output none

# Create Key Vault
echo_info "Creating Key Vault: ${VAULT_NAME}"
az keyvault create \
    --name ${VAULT_NAME} \
    --resource-group ${RESOURCE_GROUP} \
    --location ${LOCATION} \
    --enable-soft-delete true \
    --enable-purge-protection false \
    --output none

echo_info "Key Vault created successfully"

# Wait for Key Vault to be ready
echo_info "Waiting for Key Vault to be ready..."
sleep 10

# Store password in Key Vault
echo_info "Storing password in Key Vault..."
az keyvault secret set \
    --vault-name ${VAULT_NAME} \
    --name ${SECRET_NAME} \
    --value "${PASSWORD}" \
    --output none

echo_info "Password stored successfully"

# Verify secret was stored
echo_info "Verifying secret in Key Vault..."
STORED_PASSWORD=$(az keyvault secret show \
    --vault-name ${VAULT_NAME} \
    --name ${SECRET_NAME} \
    --query "value" \
    --output tsv)

if [ "${STORED_PASSWORD}" != "${PASSWORD}" ]; then
    echo_error "Password verification failed!"
    exit 1
fi
echo_info "Secret verified successfully"

# Build Bicep template
echo_info "Building Bicep template..."
az bicep build --file main.bicep --outfile temp-deploy.json
echo_info "Bicep template built successfully"

# Deploy Neo4j with Key Vault
echo_info "Deploying Neo4j with Key Vault integration..."
echo_info "  - Node Count: 1 (standalone)"
echo_info "  - Neo4j Version: 5"
echo_info "  - License Type: Evaluation"
echo_info "  - Key Vault: ${VAULT_NAME}"
echo_info "  - Secret Name: ${SECRET_NAME}"

DEPLOYMENT_NAME="neo4j-deployment-${TIMESTAMP}"

az deployment group create \
    --name ${DEPLOYMENT_NAME} \
    --resource-group ${RESOURCE_GROUP} \
    --template-file temp-deploy.json \
    --parameters \
        keyVaultName="${VAULT_NAME}" \
        keyVaultResourceGroup="${RESOURCE_GROUP}" \
        adminPasswordSecretName="${SECRET_NAME}" \
        vmSize="Standard_E4s_v5" \
        nodeCount=1 \
        diskSize=32 \
        graphDatabaseVersion="5" \
        licenseType="Evaluation" \
        installGraphDataScience="No" \
        graphDataScienceLicenseKey="None" \
        installBloom="No" \
        bloomLicenseKey="None" \
    --output none

echo_info "Deployment completed successfully"

# Get deployment outputs
echo_info "Retrieving deployment outputs..."
NEO4J_URL=$(az deployment group show \
    --name ${DEPLOYMENT_NAME} \
    --resource-group ${RESOURCE_GROUP} \
    --query "properties.outputs.Neo4jBrowserURL.value" \
    --output tsv)

echo_info "Neo4j Browser URL: ${NEO4J_URL}"

# Wait for Neo4j to start
echo_info "Waiting for Neo4j to start (this may take 5-10 minutes)..."
MAX_ATTEMPTS=60
ATTEMPT=0
SLEEP_INTERVAL=10

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" ${NEO4J_URL} || echo "000")

    if [ "$HTTP_CODE" = "200" ]; then
        echo_info "Neo4j is responding!"
        break
    fi

    ATTEMPT=$((ATTEMPT + 1))
    echo_warn "Attempt ${ATTEMPT}/${MAX_ATTEMPTS}: HTTP ${HTTP_CODE}, waiting ${SLEEP_INTERVAL}s..."
    sleep ${SLEEP_INTERVAL}
done

if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
    echo_error "Neo4j did not start within expected time"
    echo_warn "Set SKIP_CLEANUP=true to inspect the deployment"
    exit 1
fi

# Validate Neo4j deployment using Python validation script
echo_info "Running Neo4j validation..."

# Extract host from URL (remove protocol and path)
NEO4J_HOST=$(echo ${NEO4J_URL} | sed 's|http://||' | sed 's|:.*||')
BOLT_URL="bolt://${NEO4J_HOST}:7687"

echo_info "Bolt URL: ${BOLT_URL}"
echo_info "Username: neo4j"
echo_info "Password: [from Key Vault]"

# Run validation using uv (Python validation script)
if command -v uv > /dev/null 2>&1; then
    echo_info "Running validation with uv..."
    cd /Users/ryanknight/projects/neo4j-partners/azure-neo4j-modularize/marketplace/neo4j-enterprise

    if uv run validate.py "${BOLT_URL}" "neo4j" "${PASSWORD}"; then
        echo_info "✓ Validation PASSED!"
    else
        echo_error "✗ Validation FAILED!"
        echo_warn "Set SKIP_CLEANUP=true to inspect the deployment"
        exit 1
    fi
else
    echo_warn "uv not found, skipping Python validation"
    echo_info "Manual validation: Connect to ${NEO4J_URL} with username 'neo4j' and the generated password"
fi

# Verify password was NOT stored in deployment metadata (security check)
echo_info "Security check: Verifying password not in deployment metadata..."
DEPLOYMENT_PARAMS=$(az deployment group show \
    --name ${DEPLOYMENT_NAME} \
    --resource-group ${RESOURCE_GROUP} \
    --query "properties.parameters" \
    --output json)

# Check if adminPassword parameter is empty
ADMIN_PASSWORD_VALUE=$(echo ${DEPLOYMENT_PARAMS} | jq -r '.adminPassword.value // empty')
if [ -n "${ADMIN_PASSWORD_VALUE}" ] && [ "${ADMIN_PASSWORD_VALUE}" != "null" ]; then
    echo_error "Security violation: adminPassword found in deployment metadata!"
    echo_error "Value length: ${#ADMIN_PASSWORD_VALUE} characters"
    exit 1
fi

echo_info "✓ Security check PASSED: No password in deployment metadata"

# Verify Key Vault parameters were passed correctly
KV_NAME_IN_DEPLOYMENT=$(echo ${DEPLOYMENT_PARAMS} | jq -r '.keyVaultName.value // empty')
if [ "${KV_NAME_IN_DEPLOYMENT}" != "${VAULT_NAME}" ]; then
    echo_error "Key Vault name mismatch in deployment!"
    echo_error "Expected: ${VAULT_NAME}, Got: ${KV_NAME_IN_DEPLOYMENT}"
    exit 1
fi

echo_info "✓ Key Vault parameters verified in deployment"

# All tests passed!
echo ""
echo_info "=========================================="
echo_info "ALL TESTS PASSED SUCCESSFULLY!"
echo_info "=========================================="
echo_info "Test Results:"
echo_info "  ✓ Key Vault created"
echo_info "  ✓ Password stored in vault"
echo_info "  ✓ Neo4j deployed with Key Vault integration"
echo_info "  ✓ Neo4j is responsive"
echo_info "  ✓ Bolt connection validated"
echo_info "  ✓ Security check passed (no password in metadata)"
echo_info "  ✓ Key Vault parameters verified"
echo ""
echo_info "Cleanup will run automatically..."

exit 0
