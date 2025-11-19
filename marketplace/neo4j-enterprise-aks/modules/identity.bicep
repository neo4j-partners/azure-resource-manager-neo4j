// Identity Module
// Creates managed identity for Workload Identity integration

@description('Azure region for all resources')
param location string

@description('Name for the managed identity')
param identityName string

@description('Tags to apply to all resources')
param tags object = {}

// User-assigned managed identity
resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-07-31-preview' = {
  name: identityName
  location: location
  tags: tags
}

// Outputs
output identityId string = identity.id
output identityName string = identity.name
output clientId string = identity.properties.clientId
output principalId string = identity.properties.principalId
