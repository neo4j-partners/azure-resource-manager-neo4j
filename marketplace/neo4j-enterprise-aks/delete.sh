#!/bin/bash

# Delete script for Neo4j Enterprise on AKS
# Usage: ./delete.sh <resource-group-name>

set -e

# Check if resource group name is provided
if [ -z "$1" ]; then
    echo "Usage: ./delete.sh <resource-group-name>"
    echo "Example: ./delete.sh neo4j-test-aks"
    exit 1
fi

RESOURCE_GROUP=$1

echo "========================================="
echo "Neo4j Enterprise AKS Cleanup"
echo "========================================="
echo "Resource Group: $RESOURCE_GROUP"
echo ""

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    echo "Error: Azure CLI is not installed."
    exit 1
fi

# Check if logged in to Azure
az account show &> /dev/null || {
    echo "Error: Not logged in to Azure."
    echo "Please run: az login"
    exit 1
}

# Check if resource group exists
if ! az group exists --name "$RESOURCE_GROUP" | grep -q "true"; then
    echo "Resource group '$RESOURCE_GROUP' does not exist."
    exit 0
fi

# List resources in the group
echo "Resources in $RESOURCE_GROUP:"
az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name, Type:type}" --output table
echo ""

# Confirm deletion
read -p "Are you sure you want to delete resource group '$RESOURCE_GROUP' and all its resources? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Deletion cancelled."
    exit 0
fi

echo ""
echo "Deleting resource group..."
echo "This may take several minutes..."

az group delete --name "$RESOURCE_GROUP" --yes --no-wait

echo ""
echo "========================================="
echo "Deletion Initiated"
echo "========================================="
echo ""
echo "Resource group '$RESOURCE_GROUP' is being deleted in the background."
echo "This may take 5-10 minutes to complete."
echo ""
echo "To check status:"
echo "az group show --name $RESOURCE_GROUP"
echo ""
echo "When deleted, the command will return an error: 'ResourceGroupNotFound'"
echo ""
