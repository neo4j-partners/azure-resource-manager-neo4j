// Main Template - Neo4j Enterprise on Azure Kubernetes Service
// Orchestrates infrastructure and application deployment

targetScope = 'resourceGroup'

// ============================================================================
// PARAMETERS
// ============================================================================

// Location
@description('Azure region for all resources. Defaults to resource group location.')
param location string = resourceGroup().location

// Resource Naming
@description('Prefix for all resource names. Used to create unique identifiers.')
@minLength(3)
@maxLength(10)
param resourceNamePrefix string = 'neo4j'

// AKS Configuration
@description('Kubernetes version for the AKS cluster.')
param kubernetesVersion string = '1.30'

@description('VM size for system node pool (Kubernetes services).')
param systemNodeSize string = 'Standard_D2s_v5'

@description('VM size for user node pool (Neo4j workloads).')
param userNodeSize string = 'Standard_E4s_v5'

@description('Minimum number of nodes in user node pool.')
@minValue(1)
@maxValue(10)
param userNodeCountMin int = 1

@description('Maximum number of nodes in user node pool.')
@minValue(1)
@maxValue(10)
param userNodeCountMax int = 10

// Neo4j Configuration
@description('Number of Neo4j instances to deploy (1 for standalone, 3-10 for cluster).')
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
param nodeCount int = 1

@description('Neo4j graph database version.')
@allowed([
  '5'
  '4.4'
])
param graphDatabaseVersion string = '5'

@description('Size of data disk per Neo4j instance in GB.')
@minValue(32)
@maxValue(4096)
param diskSize int = 32

@description('Neo4j admin password. Must be at least 8 characters.')
@minLength(8)
@secure()
param adminPassword string

@description('Neo4j license type.')
@allowed([
  'Enterprise'
  'Evaluation'
])
param licenseType string = 'Evaluation'

// Optional: Key Vault Integration
@description('Optional: Name of Key Vault containing Neo4j admin password. Leave empty to use adminPassword parameter.')
param keyVaultName string = ''

@description('Optional: Resource group containing the Key Vault. Defaults to current resource group.')
param keyVaultResourceGroup string = resourceGroup().name

@description('Optional: Name of secret in Key Vault containing admin password.')
param adminPasswordSecretName string = 'neo4j-admin-password'

// Optional: Plugin Configuration
@description('Install Graph Data Science plugin.')
@allowed([
  'Yes'
  'No'
])
param installGraphDataScience string = 'No'

@description('Graph Data Science license key (if installing GDS).')
@secure()
param graphDataScienceLicenseKey string = ''

@description('Install Bloom plugin.')
@allowed([
  'Yes'
  'No'
])
param installBloom string = 'No'

@description('Bloom license key (if installing Bloom).')
@secure()
param bloomLicenseKey string = ''

// ============================================================================
// VARIABLES
// ============================================================================

var deploymentUniqueString = substring(uniqueString(resourceGroup().id), 0, 6)
var clusterName = '${resourceNamePrefix}-aks-${deploymentUniqueString}'
var identityName = '${resourceNamePrefix}-identity-${deploymentUniqueString}'
var namespacePrefix = 'neo4j'

// Determine if this is a standalone or cluster deployment
var isCluster = nodeCount >= 3
var deploymentType = isCluster ? 'cluster' : 'standalone'

// Tags for all resources
var commonTags = {
  'neo4j-version': graphDatabaseVersion
  'neo4j-edition': 'enterprise'
  'deployment-type': 'aks'
  'deployment-mode': deploymentType
  'node-count': string(nodeCount)
  'created-by': 'neo4j-azure-marketplace'
  'managed-by': 'bicep'
}

// Calculate initial user node count based on Neo4j node count
// For standalone (nodeCount=1), we need 1 node
// For cluster (nodeCount=3+), we need at least nodeCount nodes, but may want more for overhead
var initialUserNodeCount = nodeCount

// ============================================================================
// MODULE: Network
// ============================================================================

module network 'modules/network.bicep' = {
  name: 'network-deployment'
  params: {
    location: location
    resourceNamePrefix: resourceNamePrefix
    tags: commonTags
  }
}

// ============================================================================
// MODULE: Managed Identity
// ============================================================================

module identity 'modules/identity.bicep' = {
  name: 'identity-deployment'
  params: {
    location: location
    identityName: identityName
    tags: commonTags
  }
}

// ============================================================================
// MODULE: AKS Cluster
// ============================================================================

module aksCluster 'modules/aks-cluster.bicep' = {
  name: 'aks-deployment'
  params: {
    location: location
    clusterName: clusterName
    kubernetesVersion: kubernetesVersion
    systemSubnetId: network.outputs.systemSubnetId
    userSubnetId: network.outputs.userSubnetId
    identityId: identity.outputs.identityId
    identityPrincipalId: identity.outputs.principalId
    systemNodeSize: systemNodeSize
    userNodeSize: userNodeSize
    userNodeCountMin: userNodeCountMin
    userNodeCountMax: userNodeCountMax
    userNodeCount: initialUserNodeCount
    tags: commonTags
  }
  // Dependencies automatically inferred from parameter references
}

// ============================================================================
// MODULE: Storage Class
// ============================================================================

module storage 'modules/storage.bicep' = {
  name: 'storage-deployment'
  params: {
    location: location
    aksClusterName: aksCluster.outputs.clusterName
    aksResourceGroup: resourceGroup().name
    storageClassName: 'neo4j-premium'
    identityId: identity.outputs.identityId
  }
  // Dependencies automatically inferred from parameter references
}

// ============================================================================
// ROLE ASSIGNMENTS
// ============================================================================

// Note: Role assignment for node resource group is handled via a separate module
// because we cannot assign roles to the node resource group from the same deployment
// The managed identity has sufficient permissions through AKS's kubelet identity

// ============================================================================
// MODULE: Neo4j Application
// ============================================================================

module neo4jApp 'modules/neo4j-app.bicep' = {
  name: 'neo4j-app-deployment'
  params: {
    location: location
    aksClusterName: aksCluster.outputs.clusterName
    aksResourceGroup: resourceGroup().name
    identityId: identity.outputs.identityId
    namespaceName: namespacePrefix
    serviceAccountName: 'neo4j-sa'
    statefulSetName: 'neo4j'
    serviceName: 'neo4j'
    replicas: nodeCount
    graphDatabaseVersion: graphDatabaseVersion
    adminPassword: adminPassword
    licenseType: licenseType
    diskSize: diskSize
    installGraphDataScience: installGraphDataScience == 'Yes'
    installBloom: installBloom == 'Yes'
    cpuRequest: '2'
    memoryRequest: '8Gi'
  }
  dependsOn: [
    storage
  ]
}

// ============================================================================
// OUTPUTS
// ============================================================================

// Infrastructure Outputs
output aksClusterName string = aksCluster.outputs.clusterName
output aksClusterId string = aksCluster.outputs.clusterId
output resourceGroupName string = resourceGroup().name
output oidcIssuerUrl string = aksCluster.outputs.oidcIssuerUrl
output managedIdentityClientId string = identity.outputs.clientId
output managedIdentityPrincipalId string = identity.outputs.principalId
output logAnalyticsWorkspaceId string = aksCluster.outputs.logAnalyticsWorkspaceId
output nodeResourceGroup string = aksCluster.outputs.nodeResourceGroup

// Neo4j Application Outputs
output neo4jNamespace string = neo4jApp.outputs.namespaceName
output neo4jStatefulSet string = neo4jApp.outputs.statefulSetName
output neo4jExternalIp string = neo4jApp.outputs.externalIp
output neo4jBrowserUrl string = neo4jApp.outputs.neo4jBrowserUrl
output neo4jBoltUri string = neo4jApp.outputs.neo4jBoltUri
output neo4jUsername string = 'neo4j'

@description('Neo4j admin password')
@secure()
output neo4jPassword string = adminPassword

output connectionInstructions string = '''
# Neo4j on AKS Deployed Successfully!

## Connection Information
Browser URL:  ${neo4jApp.outputs.neo4jBrowserUrl}
Bolt URI:     ${neo4jApp.outputs.neo4jBoltUri}
Username:     neo4j
Password:     (provided during deployment)

Deployment Type: ${deploymentType}
Neo4j Version:   ${graphDatabaseVersion}
Node Count:      ${nodeCount}
License Type:    ${licenseType}

## Access Neo4j Browser
Open the Browser URL in your web browser and login with the credentials above.

Note: It may take 5-10 minutes for Neo4j pods to be fully ready after deployment.

## Verify Deployment
Get AKS credentials:
az aks get-credentials --name ${aksCluster.outputs.clusterName} --resource-group ${resourceGroup().name}

Check Neo4j pods:
kubectl get pods -n ${namespacePrefix} -w

View Neo4j logs:
kubectl logs neo4j-0 -n ${namespacePrefix}

Check services:
kubectl get services -n ${namespacePrefix}

## Troubleshooting
If you cannot connect:
1. Wait a few minutes for pods to be ready
2. Check pod status: kubectl describe pod neo4j-0 -n ${namespacePrefix}
3. Verify external IP: kubectl get service neo4j-lb -n ${namespacePrefix}

## Cleanup
To delete all resources:
./delete.sh ${resourceGroup().name}
'''
