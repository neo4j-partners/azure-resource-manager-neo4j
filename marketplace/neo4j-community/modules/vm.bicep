param location string
param resourceSuffix string
param uniqueString string
param adminUsername string
@secure()
param adminPassword string
param vmSize string
param diskSize int
param cloudInitBase64 string
param identityId string
param subnetId string

var vmName = 'vm-neo4j-${location}-${resourceSuffix}'
var nicName = 'nic-${resourceSuffix}'
var publicIpName = 'ip-neo4j-${resourceSuffix}'

resource publicIP 'Microsoft.Network/publicIPAddresses@2025-01-01' = {
  name: publicIpName
  location: location
  properties: {
    publicIPAllocationMethod: 'Dynamic'
    dnsSettings: {
      domainNameLabel: 'node-${uniqueString}'
    }
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2025-01-01' = {
  name: nicName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipConfig'
        properties: {
          primary: true
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIP.id
          }
          subnet: {
            id: subnetId
          }
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2025-04-01' = {
  name: vmName
  location: location
  tags: {
    Neo4jEdition: 'Community'
    Neo4jVersion: '5'
    DeployedBy: 'bicep-template'
    TemplateVersion: '2.0.0'
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identityId}': {}
    }
  }
  plan: {
    publisher: 'neo4j'
    product: 'neo4j-ee-vm'
    name: 'byol'
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      osDisk: {
        createOption: 'FromImage'
      }
      imageReference: {
        publisher: 'Neo4j'
        offer: 'neo4j-ee-vm'
        sku: 'byol'
        version: 'latest'
      }
      dataDisks: [
        {
          lun: 0
          createOption: 'Empty'
          managedDisk: {
            storageAccountType: 'Premium_LRS'
          }
          caching: 'None'
          diskSizeGB: diskSize
        }
      ]
    }
    osProfile: {
      computerName: 'node-${uniqueString}'
      adminUsername: adminUsername
      adminPassword: adminPassword
      customData: cloudInitBase64
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
          properties: {
            primary: true
          }
        }
      ]
    }
  }
}

// No extensions needed - using cloud-init for all configuration

output vmId string = vm.id
output vmName string = vm.name
output publicIpFqdn string = publicIP.properties.dnsSettings.fqdn
