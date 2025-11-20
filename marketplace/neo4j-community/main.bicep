@secure()
@description('Admin password for Neo4j VM. Leave empty if using Key Vault.')
param adminPassword string = ''

@description('Optional: Name of Azure Key Vault containing the admin password secret. If provided, password is retrieved from vault instead of using adminPassword parameter.')
param keyVaultName string = ''

@description('Optional: Resource group containing the Key Vault. Defaults to current resource group if not specified.')
param keyVaultResourceGroup string = ''

@description('Name of the secret in Key Vault that contains the admin password.')
param adminPasswordSecretName string = 'neo4j-admin-password'

@description('VM size for Neo4j instance')
param vmSize string = 'Standard_B2s'

@description('Data disk size in GB')
param diskSize int

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Optional UTC value for testing. Leave empty for deterministic deployments.')
param utcValue string = ''

var deploymentUniqueId = uniqueString(resourceGroup().id, deployment().name)
var resourceSuffix = utcValue != '' ? utcValue : deploymentUniqueId
var adminUsername = 'neo4j'

// Determine if using Key Vault mode
var useKeyVault = keyVaultName != ''

// Cloud-init configuration for standalone deployment
var cloudInitStandalone = loadTextContent('../../scripts/neo4j-community/cloud-init/standalone.yaml')

// Determine password source (Key Vault or direct parameter)
var passwordPlaceholder = useKeyVault ? 'RETRIEVE_FROM_KEYVAULT' : adminPassword
var vaultNameForCloudInit = useKeyVault ? keyVaultName : ''
var secretNameForCloudInit = useKeyVault ? adminPasswordSecretName : ''

// Base64 encode the password for safe passing through cloud-init
// Note: This is for avoiding shell escaping issues, NOT for security/encryption
// The adminPassword parameter is already marked @secure() for encryption in deployment metadata
var passwordBase64 = base64(passwordPlaceholder)

// Cloud-init processing (sequential variable assignments for readability)
var cloudInitStep1 = replace(cloudInitStandalone, '\${unique_string}', deploymentUniqueId)
var cloudInitStep2 = replace(cloudInitStep1, '\${location}', location)
var cloudInitStep3 = replace(cloudInitStep2, '\${admin_password}', passwordBase64)
var cloudInitStep4 = replace(cloudInitStep3, '\${key_vault_name}', vaultNameForCloudInit)
var cloudInitStep5 = replace(cloudInitStep4, '\${admin_password_secret_name}', secretNameForCloudInit)
var cloudInitData = cloudInitStep5
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
