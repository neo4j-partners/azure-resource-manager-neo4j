#!/bin/bash
set -e

# Neo4j Enterprise Azure Deployment Script
# Deploys Neo4j Enterprise using Bicep template

# Check if resource group name provided
if [ -z "$1" ]; then
    echo "Usage: ./deploy.sh <resource-group-name>"
    exit 1
fi

resourceGroup="$1"
location="westeurope"
deploymentName="Neo4jDeployment-$(date +%Y%m%d-%H%M%S)"

echo "========================================="
echo "Neo4j Enterprise Azure Deployment"
echo "========================================="
echo "Resource Group: $resourceGroup"
echo "Location: $location"
echo "Deployment Name: $deploymentName"
echo ""

# Create resource group
echo "Creating resource group..."
az group create -l $location -n $resourceGroup

# Build Bicep to ARM JSON
echo ""
echo "Building Bicep template to ARM JSON..."
az bicep build --file mainTemplate.bicep --outfile mainTemplate-generated.json

# Deploy using compiled ARM JSON
echo ""
echo "Deploying Neo4j Enterprise..."
az deployment group create \
    -g $resourceGroup \
    -n $deploymentName \
    --template-file mainTemplate-generated.json \
    --parameters @parameters.json

# Clean up generated JSON after deployment
echo ""
echo "Cleaning up temporary files..."
rm -f mainTemplate-generated.json

echo ""
echo "========================================="
echo "Deployment Complete!"
echo "========================================="
echo ""
echo "To check deployment status:"
echo "  az deployment group show -g $resourceGroup -n $deploymentName"
echo ""
echo "To view outputs:"
echo "  az deployment group show -g $resourceGroup -n $deploymentName --query properties.outputs"
echo ""
