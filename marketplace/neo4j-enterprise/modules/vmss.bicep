param location string
param resourceSuffix string
param adminUsername string
@secure()
param adminPassword string
param graphDatabaseVersion string
param licenseType string
param nodeCount int
param vmSize string
param diskSize int
param cloudInitBase64 string
param identityId string
param subnetId string
param loadBalancerBackendAddressPools array
param loadBalancerCondition bool

var vmScaleSetsName = 'vmss-neo4j-${location}-${resourceSuffix}'

resource vmScaleSets 'Microsoft.Compute/virtualMachineScaleSets@2025-04-01' = {
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
      '${identityId}': {}
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
        customData: cloudInitBase64
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
                      id: subnetId
                    }
                    publicIPAddressConfiguration: {
                      name: 'public'
                      properties: {
                        idleTimeoutInMinutes: 30
                        dnsSettings: {
                          domainNameLabel: 'neo4j-${resourceSuffix}'
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
        // No extensions needed - using cloud-init for all configuration
        extensions: []
      }
    }
  }
}

output vmScaleSetsId string = vmScaleSets.id
output vmScaleSetsName string = vmScaleSets.name