param (
    [string]$resourceGroupParam = "deployment"
 )

$resourceGroup = $resourceGroupParam
$deployment = "couchbase" + $resourceGroup
$templateUri = "https://raw.githubusercontent.com/neo4j-partners/azure-resource-manager-neo4j/master/simple/mainTemplate.json"

New-AzureRmResourceGroup -Name $resourceGroup -Location westus
New-AzureRmResourceGroupDeployment -Name $deployment -ResourceGroupName $resourceGroup -TemplateUri $templateUri -TemplateParameterFile mainTemplateParameters.json
