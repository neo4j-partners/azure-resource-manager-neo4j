@description('Azure region for all resources.')
param location string

@description('Unique suffix for resource naming.')
param resourceSuffix string

var networkSGName = 'nsg-neo4j-${location}-${resourceSuffix}'
var vnetName = 'vnet-neo4j-${location}-${resourceSuffix}'

resource networkSG 'Microsoft.Network/networkSecurityGroups@2025-05-01' = {
  name: networkSGName
  location: location
  tags: {
    Neo4jEdition: 'Community'
    DeployedBy: 'arm-template'
  }
  properties: {
    securityRules: [
      {
        name: 'SSH'
        properties: {
          description: 'SSH'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'HTTPS'
        properties: {
          description: 'HTTPS'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '7473'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 101
          direction: 'Inbound'
        }
      }
      {
        name: 'HTTP'
        properties: {
          description: 'HTTP'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '7474'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 102
          direction: 'Inbound'
        }
      }
      {
        name: 'Bolt'
        properties: {
          description: 'Bolt'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '7687'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 103
          direction: 'Inbound'
        }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2025-05-01' = {
  name: vnetName
  location: location
  tags: {
    Neo4jEdition: 'Community'
    DeployedBy: 'arm-template'
  }
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'subnet'
        properties: {
          addressPrefix: '10.0.0.0/16'
          networkSecurityGroup: {
            id: networkSG.id
          }
        }
      }
    ]
  }
}

output vnetId string = vnet.id
output subnetId string = vnet.properties.subnets[0].id
output nsgId string = networkSG.id
