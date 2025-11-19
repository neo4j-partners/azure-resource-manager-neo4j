param location string
param resourceSuffix string
param loadBalancerCondition bool

var loadBalancerName = 'lb-neo4j-${location}-${resourceSuffix}'
var publicIpName = 'ip-neo4j-${location}-${resourceSuffix}'

var loadBalancerBackendAddressPools = [
  {
    id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', loadBalancerName, 'backend')
  }
]

resource publicIp 'Microsoft.Network/publicIPAddresses@2025-01-01' = if (loadBalancerCondition) {
  name: publicIpName
  location: location
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  zones: [
    '2'
    '3'
    '1'
  ]
  properties: {
    ipTags: [
      {
        ipTagType: 'RoutingPreference'
        tag: 'Internet'
      }
    ]
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: 'neo4j-lb-${resourceSuffix}'
    }
  }
}

resource loadBalancer 'Microsoft.Network/loadBalancers@2025-01-01' = if (loadBalancerCondition) {
  name: loadBalancerName
  location: location
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    backendAddressPools: [
      {
        name: 'backend'
      }
    ]
    frontendIPConfigurations: [
      {
        name: 'lbipnew'
        properties: {
          publicIPAddress: {
            id: publicIp.id
          }
        }
      }
    ]
    loadBalancingRules: [
      {
        name: 'inboundrule7474'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIpConfigurations', loadBalancerName, 'lbipnew')
          }
          frontendPort: 7474
          backendPort: 7474
          enableFloatingIP: false
          idleTimeoutInMinutes: 4
          protocol: 'Tcp'
          enableTcpReset: false
          loadDistribution: 'Default'
          disableOutboundSnat: true
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', loadBalancerName, 'backend')
          }
          backendAddressPools: [
            {
              id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', loadBalancerName, 'backend')
            }
          ]
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', loadBalancerName, 'httpprobe')
          }
        }
      }
      {
        name: 'inbound7687'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIpConfigurations', loadBalancerName, 'lbipnew')
          }
          frontendPort: 7687
          backendPort: 7687
          enableFloatingIP: false
          idleTimeoutInMinutes: 4
          protocol: 'Tcp'
          enableTcpReset: false
          loadDistribution: 'Default'
          disableOutboundSnat: true
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', loadBalancerName, 'backend')
          }
          backendAddressPools: [
            {
              id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', loadBalancerName, 'backend')
            }
          ]
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', loadBalancerName, 'boltprobe')
          }
        }
      }
    ]
    probes: [
      {
        name: 'httpprobe'
        properties: {
          protocol: 'Http'
          port: 7474
          requestPath: '/'
          intervalInSeconds: 5
          numberOfProbes: 1
          probeThreshold: 1
        }
      }
      {
        name: 'boltprobe'
        properties: {
          protocol: 'Tcp'
          port: 7687
          intervalInSeconds: 5
          numberOfProbes: 1
          probeThreshold: 1
        }
      }
    ]
  }
}

output loadBalancerBackendAddressPools array = (loadBalancerCondition ? loadBalancer.properties.backendAddressPools : [])
output publicIpAddress string = (loadBalancerCondition ? publicIp.properties.ipAddress : '')
output publicIpFqdn string = (loadBalancerCondition ? publicIp.properties.dnsSettings.fqdn : '')