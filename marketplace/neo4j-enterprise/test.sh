#!/bin/bash
# Simple test script for Neo4j Enterprise standalone deployment

set -e

echo "========================================"
echo "Neo4j Enterprise Standalone Test"
echo "========================================"
echo ""

# Generate unique resource group name
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
RESOURCE_GROUP="neo4j-test-${TIMESTAMP}"
LOCATION="eastus"
PASSWORD="Neo4jTest$(openssl rand -base64 12 | tr -d '/+=')"

echo "Resource Group: ${RESOURCE_GROUP}"
echo "Location: ${LOCATION}"
echo "Password: ${PASSWORD}"
echo ""

# Create resource group
echo "Creating resource group..."
az group create --name ${RESOURCE_GROUP} --location ${LOCATION} --output none

# Deploy Neo4j
echo "Deploying Neo4j (this takes 5-10 minutes)..."
az deployment group create \
  --resource-group ${RESOURCE_GROUP} \
  --template-file main.bicep \
  --parameters adminPassword="${PASSWORD}" \
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

# Get Neo4j URL
echo ""
echo "Getting Neo4j URL..."
DEPLOYMENT_NAME=$(az deployment group list --resource-group ${RESOURCE_GROUP} --query "[0].name" -o tsv)
NEO4J_URL=$(az deployment group show \
  --resource-group ${RESOURCE_GROUP} \
  --name ${DEPLOYMENT_NAME} \
  --query properties.outputs.neo4jBrowserURL.value \
  -o tsv)

echo ""
echo "========================================"
echo "Deployment Complete!"
echo "========================================"
echo ""
echo "Neo4j Browser URL: ${NEO4J_URL}"
echo "Username: neo4j"
echo "Password: ${PASSWORD}"
echo ""
echo "Waiting for Neo4j to start (this may take 2-5 minutes)..."

# Wait for Neo4j to be ready
MAX_ATTEMPTS=60
ATTEMPT=0
while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
  if curl -s -o /dev/null -w "%{http_code}" ${NEO4J_URL} | grep -q "200"; then
    echo ""
    echo "✓ Neo4j HTTP endpoint is ready!"
    echo ""

    # Get Bolt URL by replacing http with bolt and port
    BOLT_URL=$(echo ${NEO4J_URL} | sed 's|http://|bolt://|' | sed 's|:7474|:7687|')

    # Run Python validation
    echo "Running Neo4j driver validation..."
    echo ""
    if uv run validate.py "${BOLT_URL}" neo4j "${PASSWORD}"; then
      echo ""
      echo "========================================"
      echo "✅ All Tests Passed!"
      echo "========================================"
      echo "✓ Deployment successful"
      echo "✓ Neo4j HTTP endpoint responding"
      echo "✓ Neo4j Bolt driver working"
      echo "✓ Database queries working"
      echo ""
      echo "Neo4j Browser: ${NEO4J_URL}"
      echo "Username: neo4j"
      echo "Password: ${PASSWORD}"
      echo ""
      echo "To clean up when done:"
      echo "  az group delete --name ${RESOURCE_GROUP} --yes"
      echo ""
      exit 0
    else
      echo ""
      echo "⚠ HTTP endpoint is up but driver validation failed"
      echo "Check the Neo4j logs for issues"
      echo ""
      exit 1
    fi
  fi
  ATTEMPT=$((ATTEMPT + 1))
  echo -n "."
  sleep 5
done

echo ""
echo "⚠ Neo4j did not respond in time. It may still be starting."
echo "Check status manually:"
echo "  curl -I ${NEO4J_URL}"
echo ""
echo "To clean up:"
echo "  az group delete --name ${RESOURCE_GROUP} --yes"
echo ""
exit 1
