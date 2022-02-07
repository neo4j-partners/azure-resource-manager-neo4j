#!/usr/bin/env bash

# This script creates a zip of our archive to publish in the marketplace

mkdir tmp
cd tmp

mkdir scripts
cp ../../scripts/node.sh ./scripts
cp ../mainTemplate.json ./
cp ../createUiDefinition.json ./

zip ../archive.zip *
cd -
rm -rf tmp