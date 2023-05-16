# marketplace
This template is used by the Neo4j Azure Marketplace offer.  It is not intended to be used outside the marketplace.

Unless you are a Neo4j employee updating the Azure Marketplace listing, you probably want to be using either the Marketplace listing itself.

# Test the Template
Documentation on how to do this is [here](https://docs.microsoft.com/en-us/azure/azure-resource-manager/templates/test-toolkit).  I haven't been able to get that working and have just used the portal.

# Execute the marketplace template locally
Update the marketplace/parameters.json to use the required params. 

#### Note: Update the _artifactsLocation under parameters.json to the required path
```
  "_artifactsLocation": {
    "value": "https://raw.githubusercontent.com/neo4j-partners/azure-resource-manager-neo4j/Neo4j-5/"
  }
  
  # Here Neo4j-5 is a branch name , replace it with the required branch name on which testing needs to be done.
  # This path is used in the fileUris parameter in mainTemplate.json
```

Execute the below script under marketplace directory 

#### Note: The resource group name provided will be created by the script automatically

```
cd marketplace
./deploy.sh <resource-group-name>

```

After testing use the below script to delete the above resource group

```
cd marketplace
./delete.sh <resource-group-name>

```

# Build the Archive and Upload
To update the listing, run [makeArchive.sh](markArchive.sh).  Then upload the resulting archive.zip to the [Partner Portal](https://partner.microsoft.com/en-us/dashboard/commercial-marketplace/overview).

# Build VM Image
This describes how we build the VM that the templates use.  Users should not need to do this.

There's a newer feature called [Azure Image Gallery](https://docs.microsoft.com/en-us/azure/marketplace/azure-vm-use-approved-base#capture-image).  That requires the Azure AD be the same as the publisher one.  Our isn't.  I set up another Azure account and started down that path, but decided that we should fix the AD and come back to that appraoach later.

So, we're taking the older SAS URI approach here.  Of course, most of the documentation has gone missing since I last did this.

## Identify the VM Image to Use
We want the latest RHEL platform image.

    az vm image list-skus --publish RedHat --location westus --offer RHEL

## Create a VM

    saAccountName=sa45345345
    resourceGroup=rg1

    az group create --name $resourceGroup --location westus
    az storage account create --sku Premium_LRS --resource-group $resourceGroup --location westus --name $saAccountName
    az vm create --name vm --resource-group $resourceGroup --image RedHat:RHEL:8_5:latest --admin-username neo4j --use-unmanaged-disk --storage-account $saAccountName --admin-password fooBar12345!

SSH into the image using the command:

    ssh neo4j@<publicIpAddress>

## Clear the History

    sudo waagent -deprovision+user -force
    exit

## Deallocate and Generalize the VM Image

    az vm deallocate --resource-group $resourceGroup --name vm
    az vm generalize --resource-group $resourceGroup --name vm

## Get the SAS URI
The portal now has a generate SAS URI button.  I just used that this last time.  What follows is a half working attempt to automate that which I'm going to punt on for now.

First off let's set the connection variable.

    az storage account show-connection-string --resource-group $resourceGroup --name $saAccountName
    connectionString="DefaultEndpointsProtocol=https;AccountName=sa34859435734;AccountKey=<your key>"

Now make sure the image is a vhd.

    az storage blob list --container-name vhds --connection-string $connectionString

We need to create a URI for the image.  

The Publish Portal could potentially print an error: "The SAS URL start date (st) for the SAS URL should be one day before the current date in UTC, please ensure that the start date for SAS link is on or before mm/dd/yyyy. Please ensure that the SAS URL is generated following the instructions available in the [help link](https://docs.microsoft.com/en-us/azure/marketplace-publishing/marketplace-publishing-vm-image-creation)."

    token=`az storage container generate-sas --name vhds --connection-string $connectionString --permissions r --expiry 2023-01-01 --output tsv`
    sasuri=`az storage blob url --container-name vhds --connection-string $connectionString --sas-token $token --name foo123`

The SAS URI should look like this:

    https://sa45345345.blob.core.windows.net/vhds/osdisk_b91e6a0e9a.vhd?sp=r&st=2022-01-30T02:07:41Z&se=2023-01-30T10:07:41Z&spr=https&sv=2020-08-04&sr=b&sig=XXXXX

Make sure it works by running:

    wget $uri

Once you can successfully get the image, drop it into the Partner Portal.
