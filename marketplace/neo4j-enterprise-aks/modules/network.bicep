// Network Module
// Creates virtual network, subnets, and network security group for AKS deployment

@description('Azure region for all resources')
param location string

@description('Prefix for resource names')
param resourceNamePrefix string

@description('Address space for virtual network')
param vnetAddressSpace string = '10.0.0.0/8'

@description('Address prefix for system node pool subnet')
param systemSubnetPrefix string = '10.0.0.0/16'

@description('Address prefix for user node pool subnet')
param userSubnetPrefix string = '10.1.0.0/16'

@description('Tags to apply to all resources')
param tags object = {}

// Virtual Network
resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: '${resourceNamePrefix}-vnet'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressSpace
      ]
    }
    subnets: [
      {
        name: 'system-subnet'
        properties: {
          addressPrefix: systemSubnetPrefix
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      {
        name: 'user-subnet'
        properties: {
          addressPrefix: userSubnetPrefix
          networkSecurityGroup: {
            id: nsg.id
          }
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          serviceEndpoints: [
            {
              service: 'Microsoft.Storage'
            }
            {
              service: 'Microsoft.KeyVault'
            }
          ]
        }
      }
    ]
  }
}

// Network Security Group for user subnet (Neo4j workloads)
resource nsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: '${resourceNamePrefix}-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowNeo4jBolt'
        properties: {
          description: 'Allow Neo4j Bolt protocol (client connections)'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '7687'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowNeo4jHTTP'
        properties: {
          description: 'Allow Neo4j Browser HTTP'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '7474'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 101
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowNeo4jHTTPS'
        properties: {
          description: 'Allow Neo4j Browser HTTPS'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '7473'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 102
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowNeo4jClusterTransaction'
        properties: {
          description: 'Allow Neo4j cluster transaction shipping'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '6000'
          sourceAddressPrefix: userSubnetPrefix
          destinationAddressPrefix: userSubnetPrefix
          access: 'Allow'
          priority: 110
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowNeo4jClusterRaft'
        properties: {
          description: 'Allow Neo4j cluster Raft consensus'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '7000'
          sourceAddressPrefix: userSubnetPrefix
          destinationAddressPrefix: userSubnetPrefix
          access: 'Allow'
          priority: 111
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowAzureLoadBalancerInbound'
        properties: {
          description: 'Allow Azure Load Balancer health probes'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 120
          direction: 'Inbound'
        }
      }
      {
        name: 'DenyAllInbound'
        properties: {
          description: 'Deny all other inbound traffic'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 4096
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowAllOutbound'
        properties: {
          description: 'Allow all outbound traffic (Azure services accessed via service endpoints)'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 100
          direction: 'Outbound'
        }
      }
    ]
  }
}

// Outputs
output vnetId string = vnet.id
output vnetName string = vnet.name
output systemSubnetId string = vnet.properties.subnets[0].id
output systemSubnetName string = vnet.properties.subnets[0].name
output userSubnetId string = vnet.properties.subnets[1].id
output userSubnetName string = vnet.properties.subnets[1].name
output nsgId string = nsg.id
output nsgName string = nsg.name
