# create a resource group
resourceGroup="neo4j_test"
location="westeurope"
az group create -l $location -n $resourceGroup

# perform the initial deployment
deploymentName="MyDeployment"
az deployment group create -g $resourceGroup -n $deploymentName \
        --template-file mainTemplate.json \
        --parameters @parameters.json
