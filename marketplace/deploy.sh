# create a resource group
resourceGroup="edr-rg-08Feb22-2"
location="westeurope"
az group create -l $location -n $resourceGroup

# perform the initial deployment
deploymentName="edr-test-08Feb22-2"
az deployment group create -g $resourceGroup -n $deploymentName \
        --template-file mainTemplate.json \
        --parameters @parameters.json
