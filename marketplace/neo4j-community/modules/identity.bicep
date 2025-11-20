param location string
param resourceSuffix string

var identityName = 'usermanaged-neo4j-${location}-${resourceSuffix}'

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
}

output identityId string = identity.id
output identityPrincipalId string = identity.properties.principalId
output identityName string = identity.name
