#!/bin/bash
# Deploy Neo4j Community Edition using Bicep template

resourceGroup="$1"
location="westeurope"

if [ -z "$resourceGroup" ]; then
  echo "Usage: ./deploy.sh <resource-group-name>"
  exit 1
fi

echo "Creating resource group: $resourceGroup"
az group create -l $location -n $resourceGroup

echo "Deploying Neo4j Community Edition..."
deploymentName="neo4j-community-$(date +%s)"
az deployment group create -g $resourceGroup -n $deploymentName \
        --template-file main.bicep \
        --parameters @parameters.json

echo "Deployment complete!"
echo "Run: az deployment group show -g $resourceGroup -n $deploymentName --query properties.outputs"
