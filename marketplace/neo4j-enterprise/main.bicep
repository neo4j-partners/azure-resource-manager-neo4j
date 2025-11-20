@secure()
@description('Admin password for Neo4j VMs.')
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

var deploymentUniqueId = uniqueString(resourceGroup().id, deployment().name)
var resourceSuffix = utcValue != '' ? utcValue : deploymentUniqueId

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

var readReplicaEnabledCondition = ((readReplicaCount >= 1) && (graphDatabaseVersion == '4.4'))
var loadBalancerCondition = ((nodeCount >= 3) || readReplicaEnabledCondition)

module loadbalancer 'modules/loadbalancer.bicep' = {
  name: 'loadbalancer-deployment'
  params: {
    location: location
    resourceSuffix: resourceSuffix
    loadBalancerCondition: loadBalancerCondition
  }
}

// Cloud-init configuration for standalone, cluster, and read replica deployments
var cloudInitStandalone = loadTextContent('../../scripts/neo4j-enterprise/cloud-init/standalone.yaml')
var cloudInitCluster = loadTextContent('../../scripts/neo4j-enterprise/cloud-init/cluster.yaml')
var cloudInitReadReplica = loadTextContent('../../scripts/neo4j-enterprise/cloud-init/read-replica.yaml')

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

// Read replica cloud-init processing (4.4 only) - sequential for readability
var rrStep1 = replace(cloudInitReadReplica, '\${admin_password}', passwordBase64)
var rrStep2 = replace(rrStep1, '\${identity_id}', identity.outputs.identityId)
var rrStep3 = replace(rrStep2, '\${resource_group}', resourceGroup().name)
var rrStep4 = replace(rrStep3, '\${vmss_name}', vmss.outputs.vmScaleSetsName)
var rrStep5 = replace(rrStep4, '\${install_gds}', installGraphDataScience)
var rrStep6 = replace(rrStep5, '\${gds_license_key}', graphDataScienceLicenseKey)
var rrStep7 = replace(rrStep6, '\${install_bloom}', installBloom)
var rrStep8 = replace(rrStep7, '\${bloom_license_key}', bloomLicenseKey)
var cloudInitReadReplicaData = rrStep8
var cloudInitReadReplicaBase64 = base64(cloudInitReadReplicaData)

var adminUsername = 'neo4j'

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

module readReplicaVmss 'modules/vmss-read-replica.bicep' = if (readReplicaEnabledCondition) {
  name: 'read-replica-vmss-deployment'
  params: {
    location: location
    resourceSuffix: resourceSuffix
    adminPassword: adminPassword
    readReplicaVmSize: readReplicaVmSize
    readReplicaCount: readReplicaCount
    readReplicaDiskSize: readReplicaDiskSize
    identityId: identity.outputs.identityId
    subnetId: network.outputs.subnetId
    loadBalancerBackendAddressPools: loadbalancer.outputs.loadBalancerBackendAddressPools
    adminUsername: adminUsername
    cloudInitBase64: cloudInitReadReplicaBase64
  }
  dependsOn: [
    vmss
  ]
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
output Neo4jClusterBloomURL string = loadBalancerCondition ? uri('http://${loadbalancer.outputs.publicIpFqdn}:7474', 'bloom') : ''
output Neo4jBloomURL string = uri('http://vm0.neo4j-${deploymentUniqueId}.${location}.cloudapp.azure.com:7474', 'bloom')
output Username string = 'neo4j'
