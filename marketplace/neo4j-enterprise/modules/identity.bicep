param location string
param resourceSuffix string

var userAssignedIdentityName = 'usermanaged-neo4j-${location}-${resourceSuffix}'

resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: userAssignedIdentityName
  location: location
}

output identityId string = userAssignedIdentity.id
output identityPrincipalId string = userAssignedIdentity.properties.principalId