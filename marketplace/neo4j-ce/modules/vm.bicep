@description('Azure region for all resources.')
param location string

@description('Unique suffix for resource naming.')
param resourceSuffix string

@description('Admin username for SSH access.')
param adminUsername string

@secure()
@description('Admin password for Neo4j and SSH access.')
param adminPassword string

@description('Neo4j version branch (latest or 5).')
param graphDatabaseVersion string

@description('Azure VM size.')
param vmSize string

@description('Base64-encoded cloud-init configuration.')
param cloudInitBase64 string

@description('Resource ID of the subnet.')
param subnetId string

@description('Resource ID of the standalone managed data disk.')
param dataDiskId string

@description('Name of the standalone managed data disk.')
param dataDiskName string

@description('Whether the target region supports availability zones.')
param useZones bool

var vmName = 'vm-neo4j-${location}-${resourceSuffix}'
var publicIpName = 'pip-neo4j-${location}-${resourceSuffix}'
var nicName = 'nic-neo4j-${location}-${resourceSuffix}'

resource publicIp 'Microsoft.Network/publicIPAddresses@2025-05-01' = {
  name: publicIpName
  location: location
  zones: useZones ? ['1'] : null
  tags: {
    Neo4jEdition: 'Community'
    DeployedBy: 'arm-template'
  }
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    idleTimeoutInMinutes: 30
    dnsSettings: {
      domainNameLabel: 'neo4j-${resourceSuffix}'
    }
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2025-05-01' = {
  name: nicName
  location: location
  tags: {
    Neo4jEdition: 'Community'
    DeployedBy: 'arm-template'
  }
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig'
        properties: {
          subnet: {
            id: subnetId
          }
          publicIPAddress: {
            id: publicIp.id
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2025-04-01' = {
  name: vmName
  location: location
  zones: useZones ? ['1'] : null
  tags: {
    Neo4jVersion: graphDatabaseVersion
    Neo4jEdition: 'Community'
    DeployedBy: 'arm-template'
    TemplateVersion: '2.0.0'
  }
  plan: {
    publisher: 'neo4j'
    product: 'neo4j-ce-vm'
    name: 'per-core-hour'
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      osDisk: {
        createOption: 'FromImage'
        caching: 'ReadWrite'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
      }
      imageReference: {
        publisher: 'neo4j'
        offer: 'neo4j-ce-vm'
        sku: 'per-core-hour'
        version: 'latest'
      }
      dataDisks: [
        {
          lun: 0
          name: dataDiskName
          createOption: 'Attach'
          managedDisk: {
            id: dataDiskId
          }
          caching: 'None'
          deleteOption: 'Detach'
        }
      ]
    }
    osProfile: {
      computerName: 'neo4j-ce'
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

output vmId string = vm.id
output vmName string = vm.name
output publicIpFqdn string = publicIp.properties.dnsSettings.fqdn
