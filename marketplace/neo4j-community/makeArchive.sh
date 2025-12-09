#!/usr/bin/env bash

# This script creates a zip of our archive to publish community edition in the marketplace

echo "Building Bicep template to ARM JSON..."
az bicep build --file main.bicep --outfile mainTemplate.json

echo "Creating marketplace archive..."
mkdir tmp
cd tmp

# Copy ARM template and UI definition (scripts are embedded in cloud-init, no external files needed)
cp ../mainTemplate.json ./
cp ../createUiDefinition.json ./

zip -r ../archive.zip *
cd -
rm -rf tmp

echo "Archive created successfully: archive.zip"
echo "Contents:"
unzip -l archive.zip
