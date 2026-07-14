# marketplace
This files are used by the Neo4j Azure Marketplace offers.  Unless you are a Neo4j employee updating the Azure Marketplace listing you shouldn't need to use these.

## Build the archive and upload
To update the listing, run [makeArchive.sh](markArchive.sh).  Then upload the resulting `archive-ce.zip` and `archive-ee.zip` to the [Microsoft Partner Center](https://partner.microsoft.com/en-us/dashboard/commercial-marketplace/overview).

## Build VM Image
This describes how we build the VM images that the templates use.  Users should not need to do this.

First we need to identify the VM image to use. We want the latest RHEL platform image.

```bash
az vm image list-skus --publish RedHat --location westus --offer RHEL
```

Now, let's create a VM

```bash
saAccountName=sa45345345
resourceGroup=rg1

az group create --name $resourceGroup --location westus
az storage account create --sku Premium_LRS --resource-group $resourceGroup --location westus --name $saAccountName
az vm create --name vm --resource-group $resourceGroup --image RedHat:RHEL:8_5:latest --admin-username neo4j --use-unmanaged-disk --storage-account $saAccountName --admin-password fooBar12345!
```
SSH into the image using the command:

```bash
ssh neo4j@<publicIpAddress>
```

Clear the History

```bash
sudo waagent -deprovision+user -force
exit
```

Deallocate and Generalize the VM Image

```bash
az vm deallocate --resource-group $resourceGroup --name vm
az vm generalize --resource-group $resourceGroup --name vm
```

## Get the SAS URI
The portal now has a generate SAS URI button.  I just used that this last time.  What follows is a half working attempt to automate that which I'm going to punt on for now.

First off let's set the connection variable.

```bash
az storage account show-connection-string --resource-group $resourceGroup --name $saAccountName
connectionString="DefaultEndpointsProtocol=https;AccountName=sa34859435734;AccountKey=<your key>"
```

Now make sure the image is a vhd.

```bash
az storage blob list --container-name vhds --connection-string $connectionString
```

We need to create a URI for the image.

The Publish Portal could potentially print an error: "The SAS URL start date (st) for the SAS URL should be one day before the current date in UTC, please ensure that the start date for SAS link is on or before mm/dd/yyyy. Please ensure that the SAS URL is generated following the instructions available in the [help link](https://docs.microsoft.com/en-us/azure/marketplace-publishing/marketplace-publishing-vm-image-creation)."

```bash
token=`az storage container generate-sas --name vhds --connection-string $connectionString --permissions r --expiry 2023-01-01 --output tsv`
sasuri=`az storage blob url --container-name vhds --connection-string $connectionString --sas-token $token --name foo123`
```
The SAS URI should look like this:

```html
https://sa45345345.blob.core.windows.net/vhds/osdisk_b91e6a0e9a.vhd?sp=r&st=2022-01-30T02:07:41Z&se=2023-01-30T10:07:41Z&spr=https&sv=2020-08-04&sr=b&sig=%2FNfIZWzp1pE2JcH2lQcVLx72k0M%2Fidaan%2BlNHWMzOl0%3D
```

Make sure it works by running:

```bash
wget $uri
```
Once you can successfully get the image, drop it into the publisher portal.