#!/bin/sh

RESOURCE_GROUP=$1

az group create --name $RESOURCE_GROUP --location westus
az group deployment create --template-file mainTemplate.json --parameters @mainTemplateParameters.json --resource-group $RESOURCE_GROUP