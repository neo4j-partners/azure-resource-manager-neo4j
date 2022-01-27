# marketplace

This template is used by the Neo4j Azure Marketplace offer.  It is not intended to be used outside the marketplace. [makeArchive.sh](makeArchive.sh) will build a zip file that can be uploaded to the publish portal. 

Unless you are a Neo4j employee updating the Azure Marketplace listing, you probably want to be using either the Marketplace listing itself or [simple](../simple).

# Testing the createUiDefinition

The [createUiDefinition.json](createUiDefinition.json) file can be tested by following this [link](https://portal.azure.com/?clientOptimizations=false#blade/Microsoft_Azure_Compute/CreateMultiVmWizardBlade/internal_bladeCallId/anything/internal_bladeCallerParams/%7B%22initialData%22:%7B%7D,%22providerConfig%22:%7B%22createUiDefinition%22:%22https%3A%2F%2Fraw.githubusercontent.com%2Fneo4j-partners%2Fazure-resource-manager-neo4j%2Fmaster%2Fmarketplace%2FcreateUiDefinition.json%22%7D%7D)

Note --- It seems like the test link doesn't work anymore.

# Build VM Image

This describes how we build the VM that the templates use.  Users should not need to do this.

https://docs.microsoft.com/en-us/azure/marketplace/azure-vm-use-approved-base#capture-image

## Documentation

Documentation on the process is here.  It is incomplete at best.
* https://docs.microsoft.com/en-us/azure/virtual-machines/virtual-machines-linux-capture-image
* https://azure.microsoft.com/en-us/documentation/articles/marketplace-publishing-vm-image-creation/
* https://azure.microsoft.com/en-us/documentation/articles/virtual-machines-linux-classic-create-upload-vhd/
* https://docs.microsoft.com/en-us/azure/virtual-machines/virtual-machines-linux-classic-capture-image

## Identify the VM Image to Use

    az vm image list-skus --publish RedHat --location westus --offer RHEL

## Create a VM

    az group create --name resourcegroup --location westus
    az storage account create --sku Premium_LRS --resource-group resourcegroup --location westus --name sa34859435734
    az vm create --name vm --resource-group resourcegroup --image RedHat:RHEL:8_5:latest --admin-username neo4j --use-unmanaged-disk --storage-account sa34859435734

SSH into the image using the command:

    ssh neo4j@<publicIpAddress>

## Clear the History

    sudo waagent -deprovision+user -force
    exit

## Deallocate and Generalize the VM Image

    az vm deallocate --resource-group resourcegroup --name vm
    az vm generalize --resource-group resourcegroup --name vm

## Get the SAS URL

First off let's set the connection variable.

    azure storage account connectionstring show sa34859435734 --resource-group resourcegroup
    connection="DefaultEndpointsProtocol=https;AccountName=sa34859435734;AccountKey=<your key>"

Now make sure the image is a vhd.

    azure storage blob list vhds -c $connection

We need to create a URL for the image.  

The Publish Portal could potentially print an error: "The SAS URL start date (st) for the SAS URL should be one day before the current date in UTC, please ensure that the start date for SAS link is on or before mm/dd/yyyy. Please ensure that the SAS URL is generated following the instructions available in the [help link](https://docs.microsoft.com/en-us/azure/marketplace-publishing/marketplace-publishing-vm-image-creation)."

    azure storage container sas create vhds rl 01/01/2018 -c $connection --start 07/31/2017

The Shared Access URL should look like this:

    https://sa34859435734.blob.core.windows.net/vhds?st=2017-03-22T07%3A00%3A00Z&se=2017-04-22T07%3A00%3A00Z&sp=rl&sv=2015-04-05&sr=c&sig=6lL4F5GHcsEJ6o3UV0kwFqmjskTv0IHX6kE%2FiY4MLz4%3D

To get the SAS URL, add the name of the os disk as follows.  You can find it early in your terminal session or in the [Portal](http://portal.azure.com).  Stick that value in a variable so we can use it later.

    url="https://sa34859435734.blob.core.windows.net/vhds/osdisk_PgSDWOnoai.vhd?st=2017-03-22T07%3A00%3A00Z&se=2017-04-22T07%3A00%3A00Z&sp=rl&sv=2015-04-05&sr=c&sig=6lL4F5GHcsEJ6o3UV0kwFqmjskTv0IHX6kE%2FiY4MLz4%3D"

Make sure it works by running:

    wget $url

Once you can successfully get the image, proceed to the [Publisher Portal](https://cloudpartner.azure.com/#publisher).
