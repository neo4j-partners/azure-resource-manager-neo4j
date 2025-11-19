// Namespace Module
// Creates Kubernetes namespace for Neo4j resources

@description('Azure region for deployment scripts')
param location string

@description('Name of the AKS cluster')
param aksClusterName string

@description('Resource group containing the AKS cluster')
param aksResourceGroup string

@description('Name for the Kubernetes namespace')
param namespaceName string

@description('Managed identity for deployment script')
param identityId string

// Namespace definition as YAML
var namespaceYaml = '''
apiVersion: v1
kind: Namespace
metadata:
  name: ${namespaceName}
  labels:
    app: neo4j
    managed-by: bicep
'''

// Deployment script to create namespace
resource createNamespace 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-namespace-${uniqueString(resourceGroup().id, namespaceName)}'
  location: location
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identityId}': {}
    }
  }
  properties: {
    azCliVersion: '2.50.0'
    timeout: 'PT5M'
    retentionInterval: 'PT1H'
    environmentVariables: [
      {
        name: 'AKS_CLUSTER_NAME'
        value: aksClusterName
      }
      {
        name: 'AKS_RESOURCE_GROUP'
        value: aksResourceGroup
      }
      {
        name: 'NAMESPACE_YAML'
        value: namespaceYaml
      }
    ]
    scriptContent: '''
      #!/bin/bash
      set -e

      echo "Getting AKS credentials..."
      az aks get-credentials --name $AKS_CLUSTER_NAME --resource-group $AKS_RESOURCE_GROUP --overwrite-existing

      echo "Creating namespace..."
      echo "$NAMESPACE_YAML" | kubectl apply -f -

      echo "Verifying namespace..."
      kubectl get namespace ${namespaceName}

      echo "Namespace created successfully"
    '''
    cleanupPreference: 'OnSuccess'
  }
}

// Outputs
output namespaceName string = namespaceName
output deploymentStatus string = createNamespace.properties.provisioningState
