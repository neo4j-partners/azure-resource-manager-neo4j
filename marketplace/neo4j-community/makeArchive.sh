#!/usr/bin/env bash

# This script creates a zip of our archive to publish community edition in the marketplace

mkdir tmp
cd tmp

mkdir scripts
cp ../../../scripts/neo4j-community/node.sh ./scripts/node.sh
cp ../mainTemplate.json ./
cp ../createUiDefinition.json ./

zip -r ../archive.zip *
cd -
rm -rf tmp
