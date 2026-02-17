@description('Azure region for all resources.')
param location string

@description('Unique suffix for resource naming.')
param resourceSuffix string

@description('Size of the data disk in GB.')
param diskSize int

var diskName = 'disk-neo4j-data-${location}-${resourceSuffix}'

resource dataDisk 'Microsoft.Compute/disks@2025-01-02' = {
  name: diskName
  location: location
  sku: {
    name: 'Premium_LRS'
  }
  properties: {
    creationData: {
      createOption: 'Empty'
    }
    diskSizeGB: diskSize
  }
  tags: {
    Purpose: 'neo4j-data'
    Neo4jEdition: 'Community'
    DeployedBy: 'arm-template'
  }
}

output diskId string = dataDisk.id
output diskName string = dataDisk.name
