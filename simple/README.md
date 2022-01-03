# simple
This is an Azure Resource Manager (ARM) template that deploys Neo4j Enterprise on Azure.  It sets up Neo4j Graph Database, Graph Data Science and Bloom.  You can run it from the  CLI or using the [Azure Portal](https://portal.azure.com) with the buttons below:

[![Deploy to Azure](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazure.svg?sanitize=true)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fneo4j-partners%2Fazure-resource-manager-neo4j%2Fmain%2Fsimple%2FmainTemplate.json)
[![Deploy To Azure US Gov](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazuregov.svg?sanitize=true)](https://portal.azure.us/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fneo4j-partners%2Fazure-resource-manager-neo4j%2Fmain%2Fsimple%2FmainTemplate.json)
[![Visualize](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/visualizebutton.svg?sanitize=true)](http://armviz.io/#/?load=https%3A%2F%2Fraw.githubusercontent.com%2Fneo4j-partners%2Fazure-resource-manager-neo4j%2Fmain%2Fsimple%2FmainTemplate.json)

The template provisions a virtual network, VM Scale Sets (VMSS), Managed Disks with Premium Storage and public IPs with a DNS record per node.  It also sets up a network security group.

## Environment Setup
You will need an Azure account.

First we need to install and configure the Azure CLI.  You can install the CLI by following the instructions [here](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli).

You can confirm the CLI is working properly by running:

    az group list

Then you'll want to clone this repo.  You can do that with the command:

    git clone https://github.com/neo4j-partners/azure-resource-manager-neo4j.git
    cd azure-resource-manager-neo4j
    cd simple

## Creating a Deployment
[deploy.sh](deploy.sh) is a helper script to create a deployment.  Take a look at it, the [mainTemplateParameters.json](mainTemplateParameters.json) and modify any parameters.  Then run it as:

    ./deploy.sh <RESOURCE_GROUP_NAME>

When complete the template prints the URLs to access Couchbase Server and Couchbase Sync Gateway.

## Deleting a Deployment
To delete your deployment you can either run the command below or use the GUI in the [Azure Portal](https://portal.azure.com).

    az group delete --yes --name <RESOURCE_GROUP_NAME>

## Debugging a Deployment
Each node runs a startup script that the waagent invokes.  To debug, you can SSH into the box and view the logs. They are in the directory `/var/lib/waagent/custom-script/download/1`.
