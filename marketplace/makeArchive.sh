#!/usr/bin/env bash

# This script creates a zip of our archive to publish in the marketplace

mkdir tmp
cd tmp

cp ../../extensions/* ./
cp ../mainTemplate.json ./
cp ../createUiDefinition.json ./

zip ../archive.zip *
cd -
rm -rf tmp