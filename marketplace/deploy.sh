# create a resource group
resourceGroup="$1"
location="westeurope"
az group create -l $location -n $resourceGroup

# perform the initial deployment
deploymentName="MyDeployment12"
az deployment group create -g $resourceGroup -n $deploymentName \
        --template-file mainTemplate.json \
        --parameters @parameters.json
