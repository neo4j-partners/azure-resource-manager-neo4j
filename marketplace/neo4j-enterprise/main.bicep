@description('Admin username for SSH access to VMs.')
param adminUsername string = 'neo4j'

@secure()
@description('Admin password for Neo4j VMs.')
param adminPassword string

param vmSize string

@allowed([
  '5'
])
param graphDatabaseVersion string
param licenseType string = 'Enterprise'

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
param diskSize int

param location string = resourceGroup().location

// Customer Usage Attribution - Partner tracking GUID
#disable-next-line no-deployments-resources
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

var loadBalancerCondition = (nodeCount >= 3)

module loadbalancer 'modules/loadbalancer.bicep' = {
  name: 'loadbalancer-deployment'
  params: {
    location: location
    resourceSuffix: resourceSuffix
    loadBalancerCondition: loadBalancerCondition
  }
}

// Cloud-init configuration for standalone and cluster deployments
var cloudInitStandalone = loadTextContent('../../scripts/neo4j-enterprise/cloud-init/standalone.yaml')
var cloudInitCluster = loadTextContent('../../scripts/neo4j-enterprise/cloud-init/cluster.yaml')

// Base64 encode the password for safe passing through cloud-init
// Note: This is for avoiding shell escaping issues, NOT for security/encryption
// The adminPassword parameter is already marked @secure() for encryption in deployment metadata
var passwordBase64 = base64(adminPassword)

// Primary cluster cloud-init processing (sequential variable assignments for readability)
var cloudInitTemplate = (nodeCount == 1) ? cloudInitStandalone : cloudInitCluster
var licenseAgreement = (licenseType == 'Evaluation') ? 'eval' : 'yes'
var cloudInitStep1 = replace(cloudInitTemplate, '\${unique_string}', deploymentUniqueId)
var cloudInitStep2 = replace(cloudInitStep1, '\${location}', location)
var cloudInitStep3 = replace(cloudInitStep2, '\${admin_password}', passwordBase64)
var cloudInitStep4 = replace(cloudInitStep3, '\${license_agreement}', licenseAgreement)
var cloudInitStep5 = replace(cloudInitStep4, '\${node_count}', string(nodeCount))
var cloudInitData = cloudInitStep5
var cloudInitBase64 = base64(cloudInitData)

module vmss 'modules/vmss.bicep' = {
  name: 'vmss-deployment'
  params: {
    location: location
    resourceSuffix: resourceSuffix
    adminUsername: adminUsername
    adminPassword: adminPassword
    graphDatabaseVersion: graphDatabaseVersion
    licenseType: licenseType
    nodeCount: nodeCount
    vmSize: vmSize
    diskSize: diskSize
    cloudInitBase64: cloudInitBase64
    identityId: identity.outputs.identityId
    subnetId: network.outputs.subnetId
    loadBalancerBackendAddressPools: loadbalancer.outputs.loadBalancerBackendAddressPools
    loadBalancerCondition: loadBalancerCondition
  }
}

output vnetId string = network.outputs.vnetId
output subnetId string = network.outputs.subnetId
output nsgId string = network.outputs.nsgId
output identityId string = identity.outputs.identityId
output loadBalancerBackendAddressPools array = loadbalancer.outputs.loadBalancerBackendAddressPools
output publicIpAddress string = loadbalancer.outputs.publicIpAddress
output vmScaleSetsId string = vmss.outputs.vmScaleSetsId
output vmScaleSetsName string = vmss.outputs.vmScaleSetsName

output Neo4jBrowserURL string = uri('http://vm0.neo4j-${deploymentUniqueId}.${location}.cloudapp.azure.com:7474', '')
output Neo4jClusterBrowserURL string = loadBalancerCondition ? uri('http://${loadbalancer.outputs.publicIpFqdn}:7474', '') : ''
output Username string = 'neo4j'
