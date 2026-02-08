@description('Admin username for SSH access to VMs.')
param adminUsername string

@secure()
@minLength(12)
@maxLength(72)
@description('Admin password for Neo4j and SSH access. Must be 12-72 characters.')
param adminPassword string

@description('Azure VM size for the Neo4j instance.')
param vmSize string

@allowed([
  'latest'
  '5'
])
@description('Neo4j version branch. "latest" installs the newest CalVer release (2025.x/2026.x). "5" installs the LTS release.')
param graphDatabaseVersion string

@minValue(32)
@maxValue(4095)
@description('Size of the data disk in GB.')
param diskSize int

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Use a standard RHEL 9 image instead of the neo4j-ce-vm marketplace image. For pre-publish CI testing only.')
param useTestImage bool = false

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

// Detect availability zone support at deploy time
// Returns ['1'] in zonal regions, [] in non-zonal regions
var zones = pickZones('Microsoft.Compute', 'virtualMachines', location)
var useZones = !empty(zones)

module network 'modules/network.bicep' = {
  name: 'network-deployment'
  params: {
    location: location
    resourceSuffix: resourceSuffix
  }
}

module disk 'modules/disk.bicep' = {
  name: 'disk-deployment'
  params: {
    location: location
    resourceSuffix: resourceSuffix
    diskSize: diskSize
    useZones: useZones
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

module vm 'modules/vm.bicep' = {
  name: 'vm-deployment'
  params: {
    location: location
    resourceSuffix: resourceSuffix
    adminUsername: adminUsername
    adminPassword: adminPassword
    graphDatabaseVersion: graphDatabaseVersion
    vmSize: vmSize
    cloudInitBase64: cloudInitBase64
    subnetId: network.outputs.subnetId
    dataDiskId: disk.outputs.diskId
    dataDiskName: disk.outputs.diskName
    useZones: useZones
    useTestImage: useTestImage
  }
}

@description('Resource ID of the virtual network.')
output vnetId string = network.outputs.vnetId

@description('Resource ID of the subnet.')
output subnetId string = network.outputs.subnetId

@description('Resource ID of the network security group.')
output nsgId string = network.outputs.nsgId

@description('Resource ID of the Neo4j virtual machine.')
output vmId string = vm.outputs.vmId

@description('Name of the Neo4j virtual machine.')
output vmName string = vm.outputs.vmName

@description('Resource ID of the data disk.')
output dataDiskId string = disk.outputs.diskId

@description('URL for the Neo4j Browser interface.')
output neo4jBrowserURL string = uri('http://${vm.outputs.publicIpFqdn}:7474', '')

@description('URL for the Neo4j Bolt protocol endpoint.')
output neo4jBoltURL string = uri('bolt://${vm.outputs.publicIpFqdn}:7687', '')

@description('Default Neo4j username.')
output username string = 'neo4j'
