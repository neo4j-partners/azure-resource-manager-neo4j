#!/usr/bin/env bash

# This script creates a zip of our archive to publish enterprise edition in the marketplace

mkdir tmp
cd tmp

mkdir -p scripts/neo4j-enterprise
cp ../../../scripts/neo4j-enterprise/node.sh ./scripts/neo4j-enterprise/node.sh
cp ../../../scripts/neo4j-enterprise/node4.sh ./scripts/neo4j-enterprise/node4.sh
cp ../../../scripts/neo4j-enterprise/readreplica4.sh ./scripts/neo4j-enterprise/readreplica4.sh
cp ../mainTemplate.json ./
cp ../createUiDefinition.json ./

zip -r ../archive.zip *
cd -
rm -rf tmp
