#!/bin/bash
set -euo pipefail

# Package Neo4j Community Edition for Azure Marketplace
# Creates archive.zip for upload to Azure Partner Portal

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Packaging Neo4j Community Edition for Marketplace ==="

# Compile Bicep to ARM JSON
echo "Compiling Bicep template..."
az bicep build --file "${SCRIPT_DIR}/main.bicep" --outfile "${SCRIPT_DIR}/mainTemplate.json"

# Create archive
echo "Creating archive.zip..."
cd "${SCRIPT_DIR}"
zip archive.zip mainTemplate.json createUiDefinition.json

# Clean up compiled JSON
rm -f "${SCRIPT_DIR}/mainTemplate.json"

echo ""
echo "=== Package created: ${SCRIPT_DIR}/archive.zip ==="
echo "Upload to: https://partner.microsoft.com/en-us/dashboard/commercial-marketplace/overview"
