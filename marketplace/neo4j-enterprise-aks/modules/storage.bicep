// Storage Module
// Creates StorageClass for Neo4j persistent volumes using Azure Disk CSI driver

@description('Azure region for deployment scripts')
param location string

@description('Name of the AKS cluster')
param aksClusterName string

@description('Resource group containing the AKS cluster')
param aksResourceGroup string

@description('Name for the StorageClass')
param storageClassName string = 'neo4j-premium'

@description('Managed identity for deployment script')
param identityId string

// StorageClass definition as YAML (using string interpolation)
var storageClassYaml = 'apiVersion: storage.k8s.io/v1\nkind: StorageClass\nmetadata:\n  name: ${storageClassName}\nprovisioner: disk.csi.azure.com\nparameters:\n  skuName: Premium_LRS\n  kind: Managed\n  cachingMode: ReadOnly\nreclaimPolicy: Retain\nallowVolumeExpansion: true\nvolumeBindingMode: WaitForFirstConsumer\n'

// Deployment script to create StorageClass
resource createStorageClass 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-storageclass-${uniqueString(resourceGroup().id)}'
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
    timeout: 'PT10M'
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
        name: 'STORAGE_CLASS_YAML'
        value: storageClassYaml
      }
    ]
    scriptContent: '''
      #!/bin/bash
      set -e

      echo "Installing kubectl..."
      az aks install-cli

      echo "Getting AKS credentials..."
      az aks get-credentials --name $AKS_CLUSTER_NAME --resource-group $AKS_RESOURCE_GROUP --overwrite-existing

      echo "Creating StorageClass..."
      echo "$STORAGE_CLASS_YAML" | kubectl apply -f -

      echo "Verifying StorageClass..."
      kubectl get storageclass ${storageClassName}

      echo "StorageClass created successfully"
    '''
    cleanupPreference: 'OnSuccess'
  }
}

// Outputs
output storageClassName string = storageClassName
output deploymentStatus string = createStorageClass.properties.provisioningState
