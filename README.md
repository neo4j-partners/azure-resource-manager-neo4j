# azure-resource-manager-neo4j
These are Azure Resource Manager (ARM) templates that deploy Neo4j on Azure. There are templates for Enterprise Edition (EE) and Community Edition (CE). These templates are used in Azure Marketplace listings:

* [Neo4j Enterprise Edition](https://marketplace.microsoft.com/en-us/product/neo4j.neo4j-ee)
* [Neo4j Community Edition](https://marketplace.microsoft.com/en-us/product/neo4j.neo4j-ce)

While deployable through the marketplace, it can also be useful to fork and customize the template to meet your needs.

To deploy this template from the command line, follow these instructions.

## Deployment

You can run these modules locally. However, Azure provides a preconfigured Cloud Shell that is an easier way to get started. Navigate to the [Azure Portal](http://portal.azure.com/) and open the cloud shell in the upper right.

Then you'll want to clone this repo. You can do that with the command:

    git clone https://github.com/neo4j-partners/azure-resource-manager-neo4j.git
    cd azure-resource-manager-neo4j

Pick either ce or ee.  Go to the appropriate director.  For this example, I'll use ee:

    cd ee

Take a look at [deploy.sh](deploy.sh).  If the settings in there look good, run:

    ./deploy.sh <RESOURCE_GROUP_NAME>

When complete the template prints the URLs to access Neo4j.

## Deleting your Deployment
To delete your deployment run:

    az group delete --yes --name <RESOURCE_GROUP_NAME>

## Debugging
If the Neo4j Browser isn't coming up, there's a good chance something isn't right in your deployment.  One thing to investigate is serial output from the VM.  If that looks good, the next place to check out is `/var/lib/waagent/custom-script/download/1`.
