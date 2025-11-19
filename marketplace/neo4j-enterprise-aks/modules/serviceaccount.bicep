// Service Account Module
// Creates Kubernetes service account with Workload Identity annotations

@description('Azure region for deployment scripts')
param location string

@description('Name of the AKS cluster')
param aksClusterName string

@description('Resource group containing the AKS cluster')
param aksResourceGroup string

@description('Kubernetes namespace for the service account')
param namespaceName string

@description('Name for the service account')
param serviceAccountName string

@description('Client ID of the managed identity for Workload Identity')
param managedIdentityClientId string

@description('Azure tenant ID')
param tenantId string = subscription().tenantId

@description('Managed identity for deployment script')
param identityId string

// Service Account definition as YAML
var serviceAccountYaml = '''
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${serviceAccountName}
  namespace: ${namespaceName}
  annotations:
    azure.workload.identity/client-id: "${managedIdentityClientId}"
    azure.workload.identity/tenant-id: "${tenantId}"
  labels:
    azure.workload.identity/use: "true"
    app: neo4j
    managed-by: bicep
'''

// Deployment script to create service account
resource createServiceAccount 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-serviceaccount-${uniqueString(resourceGroup().id, namespaceName)}'
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
        name: 'SERVICE_ACCOUNT_YAML'
        value: serviceAccountYaml
      }
    ]
    scriptContent: '''
      #!/bin/bash
      set -e

      echo "Getting AKS credentials..."
      az aks get-credentials --name $AKS_CLUSTER_NAME --resource-group $AKS_RESOURCE_GROUP --overwrite-existing

      echo "Creating service account..."
      echo "$SERVICE_ACCOUNT_YAML" | kubectl apply -f -

      echo "Verifying service account..."
      kubectl get serviceaccount ${serviceAccountName} -n ${namespaceName}

      echo "Service account created successfully"
    '''
    cleanupPreference: 'OnSuccess'
  }
}

// Outputs
output serviceAccountName string = serviceAccountName
output deploymentStatus string = createServiceAccount.properties.provisioningState
