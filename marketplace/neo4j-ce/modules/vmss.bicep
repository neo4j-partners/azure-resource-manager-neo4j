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

@description('Size of the data disk in GB.')
param diskSize int

@description('Base64-encoded cloud-init configuration.')
param cloudInitBase64 string

@description('Resource ID of the user-assigned managed identity.')
param identityId string

@description('Resource ID of the subnet.')
param subnetId string

var vmScaleSetsName = 'vmss-neo4j-${location}-${resourceSuffix}'

resource vmScaleSets 'Microsoft.Compute/virtualMachineScaleSets@2025-04-01' = {
  name: vmScaleSetsName
  location: location
  tags: {
    Neo4jVersion: graphDatabaseVersion
    Neo4jEdition: 'Community'
    NodeCount: '1'
    DeployedBy: 'arm-template'
    TemplateVersion: '1.0.0'
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identityId}': {}
    }
  }
  sku: {
    name: vmSize
    capacity: 1
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
          publisher: 'RedHat'
          offer: 'RHEL'
          sku: '9-lvm-gen2'
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
                  name: 'ipconfig'
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
                  }
                }
              ]
            }
          }
        ]
      }
      // Empty extensionProfile required - CE uses cloud-init instead of CustomScript extension
      extensionProfile: {
        extensions: []
      }
    }
  }
}

output vmScaleSetsId string = vmScaleSets.id
output vmScaleSetsName string = vmScaleSets.name
