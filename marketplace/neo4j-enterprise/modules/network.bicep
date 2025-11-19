param location string
param resourceSuffix string

var networkSGName = 'nsg-neo4j-${location}-${resourceSuffix}'
var vnetName = 'vnet-neo4j-${location}-${resourceSuffix}'

resource networkSG 'Microsoft.Network/networkSecurityGroups@2025-01-01' = {
  name: networkSGName
  location: location
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
      {
        name: 'ClusterCommunication'
        properties: {
          description: 'Cluster communication and transaction shipping (Neo4j 5.x)'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '6000'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 104
          direction: 'Inbound'
        }
      }
      {
        name: 'ClusterRaft'
        properties: {
          description: 'Raft consensus protocol (Neo4j 5.x)'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '7000'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 105
          direction: 'Inbound'
        }
      }
      {
        name: 'BoltRouting'
        properties: {
          description: 'Bolt routing connector for cluster-aware drivers'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '7688'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 106
          direction: 'Inbound'
        }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2025-01-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/8'
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