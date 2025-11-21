// Neo4j Application Orchestrator
// Deploys Neo4j using the official Neo4j Helm chart

@description('Azure region for deployment scripts')
param location string

@description('Name of the AKS cluster')
param aksClusterName string

@description('Resource group containing the AKS cluster')
param aksResourceGroup string

@description('Managed identity ID for deployment scripts')
param identityId string

@description('Kubernetes namespace name')
param namespaceName string = 'neo4j'

@description('Service account name')
param serviceAccountName string = 'neo4j-sa'

@description('StatefulSet name')
param statefulSetName string = 'neo4j'

@description('Service name')
param serviceName string = 'neo4j'

@description('Number of Neo4j replicas')
param replicas int

@description('Neo4j graph database version')
param graphDatabaseVersion string

@description('Neo4j admin password')
@secure()
param adminPassword string

@description('Neo4j license type')
@allowed([
  'Enterprise'
  'Evaluation'
])
param licenseType string

@description('Size of data disk per pod in GB')
param diskSize int

@description('CPU request per pod')
param cpuRequest string = '2'

@description('Memory request per pod')
param memoryRequest string = '8Gi'

@description('Enable debug mode with verbose logging')
param debugMode bool = false

// ============================================================================
// MODULE: Helm Deployment
// ============================================================================

module helmDeployment 'helm-deployment.bicep' = {
  name: 'helm-deployment'
  params: {
    location: location
    aksClusterName: aksClusterName
    aksResourceGroup: aksResourceGroup
    namespaceName: namespaceName
    releaseName: serviceName
    nodeCount: replicas
    graphDatabaseVersion: graphDatabaseVersion
    adminPassword: adminPassword
    licenseType: licenseType
    diskSize: diskSize
    cpuRequest: '${cpuRequest}000m'  // Convert to millicores (e.g., "2" -> "2000m")
    memoryRequest: memoryRequest
    debugMode: debugMode
    identityId: identityId
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================

output namespaceName string = namespaceName
output serviceAccountName string = serviceAccountName
output configMapName string = 'neo4j-config'
output secretName string = 'neo4j-secrets'
output statefulSetName string = statefulSetName
output serviceName string = helmDeployment.outputs.releaseName
output loadBalancerServiceName string = helmDeployment.outputs.releaseName
output externalIp string = helmDeployment.outputs.externalIp
output neo4jBrowserUrl string = helmDeployment.outputs.browserUrl
output neo4jBoltUri string = helmDeployment.outputs.boltUri
