@secure()
@description('Admin password for Neo4j VM.')
param adminPassword string

@description('VM size for Neo4j instance')
param vmSize string = 'Standard_B2s'

@description('Data disk size in GB')
param diskSize int

@description('Azure region for all resources')
param location string = resourceGroup().location

var deploymentUniqueId = uniqueString(resourceGroup().id, deployment().name)
var resourceSuffix = deploymentUniqueId
var adminUsername = 'neo4j'

// Cloud-init configuration for standalone deployment
var cloudInitStandalone = loadTextContent('../../scripts/neo4j-community/cloud-init/standalone.yaml')

// Base64 encode the password for safe passing through cloud-init
// Note: This is for avoiding shell escaping issues, NOT for security/encryption
// The adminPassword parameter is already marked @secure() for encryption in deployment metadata
var passwordBase64 = base64(adminPassword)

// Cloud-init processing (sequential variable assignments for readability)
var cloudInitStep1 = replace(cloudInitStandalone, '\${unique_string}', deploymentUniqueId)
var cloudInitStep2 = replace(cloudInitStep1, '\${location}', location)
var cloudInitStep3 = replace(cloudInitStep2, '\${admin_password}', passwordBase64)
var cloudInitData = cloudInitStep3
var cloudInitBase64 = base64(cloudInitData)

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

module vm 'modules/vm.bicep' = {
  name: 'vm-deployment'
  params: {
    location: location
    resourceSuffix: resourceSuffix
    uniqueString: deploymentUniqueId
    adminUsername: adminUsername
    adminPassword: adminPassword
    vmSize: vmSize
    diskSize: diskSize
    cloudInitBase64: cloudInitBase64
    identityId: identity.outputs.identityId
    subnetId: network.outputs.subnetId
  }
}

output Neo4jBrowserURL string = uri('http://node-${deploymentUniqueId}.${location}.cloudapp.azure.com:7474', '')
output Username string = 'neo4j'
output vnetId string = network.outputs.vnetId
output subnetId string = network.outputs.subnetId
output nsgId string = network.outputs.nsgId
output identityId string = identity.outputs.identityId
output vmId string = vm.outputs.vmId
output vmName string = vm.outputs.vmName
