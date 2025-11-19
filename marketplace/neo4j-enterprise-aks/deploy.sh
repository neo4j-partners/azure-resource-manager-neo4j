#!/bin/bash

# Deploy script for Neo4j Enterprise on AKS
# Usage: ./deploy.sh <resource-group-name> [location]

set -e

# Check if resource group name is provided
if [ -z "$1" ]; then
    echo "Usage: ./deploy.sh <resource-group-name> [location]"
    echo "Example: ./deploy.sh neo4j-test-aks eastus"
    exit 1
fi

RESOURCE_GROUP=$1
LOCATION=${2:-eastus}

echo "========================================="
echo "Neo4j Enterprise AKS Deployment"
echo "========================================="
echo "Resource Group: $RESOURCE_GROUP"
echo "Location: $LOCATION"
echo ""

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    echo "Error: Azure CLI is not installed."
    echo "Please install from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi

# Check if logged in to Azure
echo "Checking Azure login status..."
az account show &> /dev/null || {
    echo "Error: Not logged in to Azure."
    echo "Please run: az login"
    exit 1
}

SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
echo "Using subscription: $SUBSCRIPTION_NAME"
echo ""

# Check if Bicep is available
echo "Checking Bicep installation..."
az bicep version || {
    echo "Error: Bicep is not installed."
    echo "Please run: az bicep install"
    exit 1
}

# Create resource group if it doesn't exist
echo "Creating resource group (if not exists)..."
az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none

echo "Resource group created: $RESOURCE_GROUP"
echo ""

# Build Bicep template
echo "Building Bicep template..."
az bicep build --file main.bicep

echo "Bicep build successful"
echo ""

# Deploy template
echo "Starting deployment..."
echo "This will take approximately 10-15 minutes..."
echo ""

DEPLOYMENT_NAME="neo4j-aks-$(date +%Y%m%d-%H%M%S)"

az deployment group create \
    --name "$DEPLOYMENT_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --template-file main.bicep \
    --parameters parameters.json \
    --output table

echo ""
echo "========================================="
echo "Deployment Complete!"
echo "========================================="
echo ""

# Get and display outputs
echo "Retrieving deployment outputs..."
echo ""

AKS_CLUSTER=$(az deployment group show \
    --name "$DEPLOYMENT_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query properties.outputs.aksClusterName.value \
    -o tsv)

echo "AKS Cluster Name: $AKS_CLUSTER"
echo ""

# Get AKS credentials
echo "Getting AKS credentials..."
az aks get-credentials --name "$AKS_CLUSTER" --resource-group "$RESOURCE_GROUP" --overwrite-existing

echo ""
echo "Verifying cluster access..."
kubectl get nodes

echo ""
echo "Verifying storage class..."
kubectl get storageclass neo4j-premium

echo ""
echo "========================================="
echo "Next Steps:"
echo "========================================="
echo ""
echo "1. View cluster: kubectl get nodes"
echo "2. View storage: kubectl get storageclass"
echo "3. Deploy Neo4j (manual for now):"
echo "   helm repo add neo4j https://helm.neo4j.com/neo4j"
echo "   helm install neo4j neo4j/neo4j --set neo4j.password='YourPassword'"
echo ""
echo "To delete all resources: ./delete.sh $RESOURCE_GROUP"
echo ""
