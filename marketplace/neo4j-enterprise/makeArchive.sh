#!/usr/bin/env bash

# This script creates a zip of our archive to publish enterprise edition in the marketplace

mkdir tmp
cd tmp

mkdir scripts
cp ../../../scripts/node-enterprise/node.sh ./scripts/node-enterprise/node.sh
cp ../../../scripts/node-enterprise/node4.sh ./scripts/node-enterprise/node4.sh
cp ../../../scripts/node-enterprise/readreplica4.sh ./scripts/node-enterprise/readreplica4.sh
cp ../mainTemplate.json ./
cp ../createUiDefinition.json ./

zip -r ../archive.zip *
cd -
rm -rf tmp
