#!/bin/sh

RESOURCE_GROUP=$1

az group create --name $RESOURCE_GROUP --location westus
az deployment group create --template-file mainTemplate.json --resource-group $RESOURCE_GROUP --parameters @mainTemplateParameters.json
