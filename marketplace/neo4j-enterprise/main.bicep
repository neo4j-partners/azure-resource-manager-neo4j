@secure()
@description('Admin password for Neo4j VMs. Leave empty if using Key Vault.')
param adminPassword string = ''

@description('Optional: Name of Azure Key Vault containing the admin password secret. If provided, password is retrieved from vault instead of using adminPassword parameter.')
param keyVaultName string = ''

@description('Optional: Resource group containing the Key Vault. Defaults to current resource group if not specified.')
param keyVaultResourceGroup string = ''

@description('Name of the secret in Key Vault that contains the admin password.')
param adminPasswordSecretName string = 'neo4j-admin-password'

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

// Determine if using Key Vault mode
var useKeyVault = keyVaultName != ''

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

// Grant managed identity access to Key Vault (if using Key Vault mode)
var vaultResourceGroup = keyVaultResourceGroup != '' ? keyVaultResourceGroup : resourceGroup().name

module keyVaultAccess 'modules/keyvault-access.bicep' = if (useKeyVault) {
  name: 'keyvault-access-deployment'
  scope: resourceGroup(vaultResourceGroup)
  params: {
    keyVaultName: keyVaultName
    identityPrincipalId: identity.outputs.identityPrincipalId
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

// Determine password source (Key Vault or direct parameter)
var passwordPlaceholder = useKeyVault ? 'RETRIEVE_FROM_KEYVAULT' : adminPassword
var vaultNameForCloudInit = useKeyVault ? keyVaultName : ''
var secretNameForCloudInit = useKeyVault ? adminPasswordSecretName : ''

// Escape single quotes in password for shell safety: ' becomes '\''
// This allows the password to be safely used in single-quoted strings
var escapedPassword = replace(passwordPlaceholder, "'", "'\\''")

// Primary cluster cloud-init processing (sequential variable assignments for readability)
var cloudInitTemplate = (nodeCount == 1) ? cloudInitStandalone : cloudInitCluster
var licenseAgreement = (licenseType == 'Evaluation') ? 'eval' : 'yes'
var cloudInitStep1 = replace(cloudInitTemplate, '\${unique_string}', deploymentUniqueId)
var cloudInitStep2 = replace(cloudInitStep1, '\${location}', location)
var cloudInitStep3 = replace(cloudInitStep2, '\${admin_password}', escapedPassword)
var cloudInitStep4 = replace(cloudInitStep3, '\${license_agreement}', licenseAgreement)
var cloudInitStep5 = replace(cloudInitStep4, '\${node_count}', string(nodeCount))
var cloudInitStep6 = replace(cloudInitStep5, '\${key_vault_name}', vaultNameForCloudInit)
var cloudInitStep7 = replace(cloudInitStep6, '\${admin_password_secret_name}', secretNameForCloudInit)
var cloudInitData = cloudInitStep7
var cloudInitBase64 = base64(cloudInitData)

// Read replica cloud-init processing (4.4 only) - sequential for readability
var rrStep1 = replace(cloudInitReadReplica, '\${admin_password}', escapedPassword)
var rrStep2 = replace(rrStep1, '\${identity_id}', identity.outputs.identityId)
var rrStep3 = replace(rrStep2, '\${resource_group}', resourceGroup().name)
var rrStep4 = replace(rrStep3, '\${vmss_name}', vmss.outputs.vmScaleSetsName)
var rrStep5 = replace(rrStep4, '\${install_gds}', installGraphDataScience)
var rrStep6 = replace(rrStep5, '\${gds_license_key}', graphDataScienceLicenseKey)
var rrStep7 = replace(rrStep6, '\${install_bloom}', installBloom)
var rrStep8 = replace(rrStep7, '\${bloom_license_key}', bloomLicenseKey)
var rrStep9 = replace(rrStep8, '\${key_vault_name}', vaultNameForCloudInit)
var rrStep10 = replace(rrStep9, '\${admin_password_secret_name}', secretNameForCloudInit)
var cloudInitReadReplicaData = rrStep10
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
