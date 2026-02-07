@description('Admin username for SSH access to VMs.')
param adminUsername string = 'neo4j'

@secure()
@minLength(8)
@maxLength(72)
@description('Admin password for Neo4j and SSH access. Must be 8-72 characters.')
param adminPassword string

@description('Azure VM size for the Neo4j instance.')
param vmSize string

@allowed([
  'latest'
  '5'
])
@description('Neo4j version branch. "latest" installs the newest CalVer release (2025.x/2026.x). "5" installs the LTS release.')
param graphDatabaseVersion string

@description('Size of the data disk in GB.')
param diskSize int

@description('Azure region for all resources.')
param location string = resourceGroup().location

// Customer Usage Attribution - Partner tracking GUID
// API version is prescribed by Microsoft's CUA specification
#disable-next-line no-deployments-resources use-recent-api-versions
resource partnerUsageAttribution 'Microsoft.Resources/deployments@2021-04-01' = {
  name: 'XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX'
  properties: {
    mode: 'Incremental'
    template: {
      '$schema': 'https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#'
      contentVersion: '1.0.0.0'
      resources: []
    }
  }
}

var deploymentUniqueId = uniqueString(resourceGroup().id, deployment().name)
var resourceSuffix = deploymentUniqueId

module network 'modules/network.bicep' = {
  name: 'network-deployment'
  params: {
    location: location
    resourceSuffix: resourceSuffix
  }
}

module identity 'modules/identity.bicep' = {
  name: 'identity-deployment'
  params: {
    location: location
    resourceSuffix: resourceSuffix
  }
}

// Cloud-init configuration for standalone CE deployment
var cloudInitTemplate = loadTextContent('../../scripts/neo4j-ce/cloud-init/standalone.yaml')

// Base64 encode the password for safe passing through cloud-init
// Note: This is for avoiding shell escaping issues, NOT for security/encryption
// The adminPassword parameter is already marked @secure() for encryption in deployment metadata
var passwordBase64 = base64(adminPassword)

// Cloud-init variable substitution
var cloudInitStep1 = replace(cloudInitTemplate, '\${unique_string}', deploymentUniqueId)
var cloudInitStep2 = replace(cloudInitStep1, '\${location}', location)
var cloudInitStep3 = replace(cloudInitStep2, '\${admin_password}', passwordBase64)
var cloudInitStep4 = replace(cloudInitStep3, '\${graph_database_version}', graphDatabaseVersion)
var cloudInitData = cloudInitStep4
var cloudInitBase64 = base64(cloudInitData)

module vmss 'modules/vmss.bicep' = {
  name: 'vmss-deployment'
  params: {
    location: location
    resourceSuffix: resourceSuffix
    adminUsername: adminUsername
    adminPassword: adminPassword
    graphDatabaseVersion: graphDatabaseVersion
    vmSize: vmSize
    diskSize: diskSize
    cloudInitBase64: cloudInitBase64
    identityId: identity.outputs.identityId
    subnetId: network.outputs.subnetId
  }
}

output vnetId string = network.outputs.vnetId
output subnetId string = network.outputs.subnetId
output nsgId string = network.outputs.nsgId
output identityId string = identity.outputs.identityId
output vmScaleSetsId string = vmss.outputs.vmScaleSetsId
output vmScaleSetsName string = vmss.outputs.vmScaleSetsName

output Neo4jBrowserURL string = uri('http://vm0.neo4j-${deploymentUniqueId}.${location}.cloudapp.azure.com:7474', '')
output Username string = 'neo4j'
