@secure()
param adminPassword string
param vmSize string
param readReplicaVmSize string = 'Standard_B2s'

@allowed([
  '5'
  '4.4'
])
param graphDatabaseVersion string
param installGraphDataScience string = 'No'
param licenseType string = 'Enterprise'
param graphDataScienceLicenseKey string = 'None'
param installBloom string = 'No'
param bloomLicenseKey string

@allowed([
  1
  3
  4
  5
  6
  7
  8
  9
  10
])
param nodeCount int

@allowed([
  0
  1
  2
  3
  4
  5
  6
  7
  8
  9
  10
])
param readReplicaCount int = 0
param diskSize int
param readReplicaDiskSize int = 32
param location string = resourceGroup().location

@description('Optional UTC value for testing. Leave empty for deterministic deployments.')
param utcValue string = ''

// Load cloud-init configuration
var cloudInitStandalone = loadTextContent('../../scripts/neo4j-enterprise/cloud-init/standalone.yaml')

var deploymentUniqueId = uniqueString(resourceGroup().id, deployment().name)
// Use utcValue if provided (for testing), otherwise use deterministic deploymentUniqueId
var resourceSuffix = utcValue != '' ? utcValue : deploymentUniqueId
var loadBalancerBackendAddressPools = [
  {
    id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', loadBalancerName, 'backend')
  }
]
// Prepare cloud-init with parameter substitution
var licenseAgreement = (licenseType == 'Evaluation') ? 'eval' : 'yes'
var cloudInitData = replace(replace(replace(replace(cloudInitStandalone, '\${unique_string}', deploymentUniqueId), '\${location}', location), '\${admin_password}', adminPassword), '\${license_agreement}', licenseAgreement)
var cloudInitBase64 = base64(cloudInitData)

var networkSGName = 'nsg-neo4j-${location}-${resourceSuffix}'
var vnetName = 'vnet-neo4j-${location}-${resourceSuffix}'
var loadBalancerName = 'lb-neo4j-${location}-${resourceSuffix}'
var publicIpName = 'ip-neo4j-${location}-${resourceSuffix}'
var vmScaleSetsName = 'vmss-neo4j-${location}-${resourceSuffix}'
var readReplicaVmScaleSetsName = 'read-replica-vmss-neo4j-${location}-${resourceSuffix}'
var userAssignedIdentityName = 'usermanaged-neo4j-${location}-${resourceSuffix}'
var adminUsername = string('neo4j')
var readReplicaEnabledCondition = ((readReplicaCount >= 1) && (graphDatabaseVersion == '4.4'))
var loadBalancerCondition = ((nodeCount >= 3) || readReplicaEnabledCondition)
// Dependencies handled implicitly by Bicep through resource references

resource networkSG 'Microsoft.Network/networkSecurityGroups@2022-07-01' = {
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
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2022-07-01' = {
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

resource publicIp 'Microsoft.Network/publicIPAddresses@2022-05-01' = if (loadBalancerCondition) {
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
  }
}

resource loadBalancer 'Microsoft.Network/loadBalancers@2022-05-01' = if (loadBalancerCondition) {
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

resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: userAssignedIdentityName
  location: location
}

resource vmScaleSets 'Microsoft.Compute/virtualMachineScaleSets@2018-06-01' = {
  name: vmScaleSetsName
  location: location
  tags: {
    Neo4jVersion: graphDatabaseVersion
    Neo4jEdition: licenseType
    NodeCount: string(nodeCount)
    DeployedBy: 'arm-template'
    TemplateVersion: '1.0.0'
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentity.id}': {}
    }
  }
  plan: {
    publisher: 'neo4j'
    product: 'neo4j-ee-vm'
    name: 'byol'
  }
  sku: {
    name: vmSize
    capacity: nodeCount
  }
  properties: {
    overprovision: false
    upgradePolicy: {
      mode: 'Manual'
    }
    virtualMachineProfile: {
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
        computerNamePrefix: 'node'
        adminUsername: adminUsername
        adminPassword: adminPassword
        customData: (nodeCount == 1) ? cloudInitBase64 : null
      }
      networkProfile: {
        networkInterfaceConfigurations: [
          {
            name: 'nic'
            properties: {
              primary: true
              ipConfigurations: [
                {
                  name: 'ipconfig-cluster'
                  properties: {
                    subnet: {
                      id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, 'subnet')
                    }
                    publicIPAddressConfiguration: {
                      name: 'public'
                      properties: {
                        idleTimeoutInMinutes: 30
                        dnsSettings: {
                          domainNameLabel: 'neo4j-${deploymentUniqueId}'
                        }
                      }
                    }
                    loadBalancerBackendAddressPools: (loadBalancerCondition
                      ? loadBalancerBackendAddressPools
                      : null)
                  }
                }
              ]
            }
          }
        ]
      }
      extensionProfile: {
        extensions: (nodeCount == 1) ? [] : [
          {
            name: 'extension'
            properties: {
              publisher: 'Microsoft.Azure.Extensions'
              type: 'CustomScript'
              typeHandlerVersion: '2.0'
              autoUpgradeMinorVersion: true
              settings: {
                fileUris: [
                  'https://raw.githubusercontent.com/neo4j-partners/azure-resource-manager-neo4j/main/scripts/neo4j-enterprise/node.sh'
                ]
              }
              protectedSettings: {
                commandToExecute: 'bash node.sh ${adminUsername} "${adminPassword}" ${deploymentUniqueId} ${location} ${graphDatabaseVersion} ${installGraphDataScience} ${graphDataScienceLicenseKey} ${installBloom} ${bloomLicenseKey} ${nodeCount} ${(loadBalancerCondition?publicIp!.properties.ipAddress:'-')} /subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/${userAssignedIdentityName} ${resourceGroup().name} ${vmScaleSetsName} ${licenseType}'
              }
            }
          }
        ]
      }
    }
  }
  // Dependencies inferred automatically by Bicep from resource references
}

resource readReplicaVmScaleSets 'Microsoft.Compute/virtualMachineScaleSets@2018-06-01' = if (readReplicaEnabledCondition) {
  name: readReplicaVmScaleSetsName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentity.id}': {}
    }
  }
  plan: {
    publisher: 'neo4j'
    product: 'neo4j-ee-vm'
    name: 'byol'
  }
  sku: {
    name: readReplicaVmSize
    capacity: readReplicaCount
  }
  properties: {
    overprovision: false
    upgradePolicy: {
      mode: 'Manual'
    }
    virtualMachineProfile: {
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
            diskSizeGB: readReplicaDiskSize
          }
        ]
      }
      osProfile: {
        computerNamePrefix: 'node'
        adminUsername: adminUsername
        adminPassword: adminPassword
      }
      networkProfile: {
        networkInterfaceConfigurations: [
          {
            name: 'nic-read-replica'
            properties: {
              primary: true
              ipConfigurations: [
                {
                  name: 'ipconfig-read-replica'
                  properties: {
                    subnet: {
                      id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, 'subnet')
                    }
                    publicIPAddressConfiguration: {
                      name: 'public-read-replica'
                      properties: {
                        idleTimeoutInMinutes: 30
                        dnsSettings: {
                          domainNameLabel: 'rr-${deploymentUniqueId}'
                        }
                      }
                    }
                    loadBalancerBackendAddressPools: loadBalancerBackendAddressPools
                  }
                }
              ]
            }
          }
        ]
      }
      extensionProfile: {
        extensions: [
          {
            name: 'extension'
            properties: {
              publisher: 'Microsoft.Azure.Extensions'
              type: 'CustomScript'
              typeHandlerVersion: '2.0'
              autoUpgradeMinorVersion: true
              settings: {
                fileUris: [
                  'https://raw.githubusercontent.com/neo4j-partners/azure-resource-manager-neo4j/main/scripts/neo4j-enterprise/readreplica4.sh'
                ]
              }
              protectedSettings: {
                commandToExecute: 'bash readreplica4.sh "${adminPassword}" /subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/${userAssignedIdentityName} ${resourceGroup().name} ${vmScaleSetsName} ${installGraphDataScience} ${graphDataScienceLicenseKey} ${installBloom} ${bloomLicenseKey}'
              }
            }
          }
        ]
      }
    }
  }
  dependsOn: [
    vmScaleSets
  ]
}

output Neo4jBrowserURL string = uri('http://vm0.neo4j-${deploymentUniqueId}.${location}.cloudapp.azure.com:7474', '')
output Neo4jClusterBrowserURL string = loadBalancerCondition ? uri('http://${publicIp!.properties.ipAddress}:7474', '') : ''
output Neo4jClusterBloomURL string = loadBalancerCondition ? uri('http://${publicIp!.properties.ipAddress}:7474', 'bloom') : ''
output Neo4jBloomURL string = uri('http://vm0.neo4j-${deploymentUniqueId}.${location}.cloudapp.azure.com:7474', 'bloom')
output Username string = 'neo4j'
