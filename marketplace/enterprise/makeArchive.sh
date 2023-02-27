#!/usr/bin/env bash

# This script creates a zip of our archive to publish enterprise edition in the marketplace

mkdir tmp
cd tmp

mkdir scripts
cp ../../../scripts/node.sh ./scripts/node.sh
cp ../../../scripts/node4.sh ./scripts/node4.sh
cp ../../../scripts/readreplica4.sh ./scripts/readreplica4.sh
cp ../mainTemplate.json ./
cp ../createUiDefinition.json ./

zip -r ../archive.zip *
cd -
rm -rf tmp
