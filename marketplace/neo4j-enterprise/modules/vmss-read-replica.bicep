param location string
param resourceSuffix string
@secure()
param adminPassword string
param readReplicaVmSize string
param readReplicaCount int
param readReplicaDiskSize int
param identityId string
param subnetId string
param loadBalancerBackendAddressPools array
param adminUsername string
param cloudInitBase64 string

var readReplicaVmScaleSetsName = 'read-replica-vmss-neo4j-${location}-${resourceSuffix}'

resource readReplicaVmScaleSets 'Microsoft.Compute/virtualMachineScaleSets@2025-04-01' = {
  name: readReplicaVmScaleSetsName
  location: location
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
        customData: cloudInitBase64
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
                      id: subnetId
                    }
                    publicIPAddressConfiguration: {
                      name: 'public-read-replica'
                      properties: {
                        idleTimeoutInMinutes: 30
                        dnsSettings: {
                          domainNameLabel: 'rr-${resourceSuffix}'
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
        // No extensions needed - using cloud-init for all configuration
        extensions: []
      }
    }
  }

}