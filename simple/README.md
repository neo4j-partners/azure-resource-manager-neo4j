# simple
This is anAzure Resource Manager (ARM) template that deploys Neo4j Enterprise on Azure.  It sets up Neo4j Graph Database, Graph Data Science and Bloom.  You can run it from the  CLI or using the [Azure Portal](https://portal.azure.com).

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

    azure group delete <RESOURCE_GROUP_NAME>