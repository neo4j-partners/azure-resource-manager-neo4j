#!/usr/bin/env bash

for edition in "ee" "ce"; do
  mkdir tmp
  cd tmp

  mkdir scripts
  cp ../../$edition/scripts/startup.sh ./scripts/
  cp ../../$edition/mainTemplate.json ./
  cp ../createUiDefinition-$edition.json ./createUiDefinition.json
  zip -r ../archive-$edition.zip *

  cd ..
  rm -rf tmp
done
