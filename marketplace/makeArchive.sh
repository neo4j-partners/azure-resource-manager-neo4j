#!/usr/bin/env bash

mkdir tmp
cd tmp

mkdir scripts
cp ../../scripts/node.sh ./scripts/node.sh
cp ../mainTemplate.json ./
cp ../createUiDefinition.json ./

zip -r ../archive.zip *
cd -
rm -rf tmp
