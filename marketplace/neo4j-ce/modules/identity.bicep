@description('Azure region for all resources.')
param location string

@description('Unique suffix for resource naming.')
param resourceSuffix string

var userAssignedIdentityName = 'usermanaged-neo4j-${location}-${resourceSuffix}'

resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: userAssignedIdentityName
  location: location
}

output identityId string = userAssignedIdentity.id
output identityPrincipalId string = userAssignedIdentity.properties.principalId
