#!/usr/bin/env bash
set -e

# This script creates a zip archive for publishing Neo4j Enterprise in Azure Marketplace
# It compiles the Bicep template to ARM JSON before packaging

echo "========================================="
echo "Neo4j Enterprise Marketplace Archive"
echo "========================================="
echo ""

# Step 1: Build Bicep to ARM JSON
echo "Step 1: Building Bicep template to ARM JSON..."
az bicep build --file main.bicep --outfile mainTemplate.json

# Verify the build succeeded
if [ ! -f mainTemplate.json ]; then
    echo "ERROR: Bicep build failed - mainTemplate.json not generated"
    exit 1
fi

echo "✓ Bicep compiled successfully"
echo ""

# Step 2: Create temporary directory and copy files
echo "Step 2: Preparing archive contents..."
mkdir tmp
cd tmp

# Copy installation scripts
mkdir -p scripts/neo4j-enterprise
cp ../../../scripts/neo4j-enterprise/node.sh ./scripts/neo4j-enterprise/node.sh

# Copy compiled ARM template and UI definition
cp ../mainTemplate.json ./
cp ../createUiDefinition.json ./

echo "✓ Files copied to tmp directory"
echo ""

# Step 3: Create zip archive
echo "Step 3: Creating archive.zip..."
zip -r ../archive.zip *

echo "✓ Archive created"
echo ""

# Step 4: Cleanup
cd -
rm -rf tmp

# Clean up the generated mainTemplate.json (keep source as main.bicep)
rm -f mainTemplate.json

echo "========================================="
echo "Archive creation complete!"
echo "========================================="
echo ""
echo "Archive location: ./archive.zip"
echo ""
echo "Archive contents:"
echo "  - mainTemplate.json (compiled from main.bicep)"
echo "  - createUiDefinition.json"
echo "  - scripts/neo4j-enterprise/node.sh"
echo ""
echo "Ready for Azure Marketplace publishing!"
echo ""
