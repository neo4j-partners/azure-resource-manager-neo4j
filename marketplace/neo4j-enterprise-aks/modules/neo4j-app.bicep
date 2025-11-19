// Neo4j Application Orchestrator
// Deploys all Kubernetes resources for Neo4j application layer

@description('Azure region for deployment scripts')
param location string

@description('Name of the AKS cluster')
param aksClusterName string

@description('Resource group containing the AKS cluster')
param aksResourceGroup string

@description('Managed identity ID for deployment scripts')
param identityId string

@description('Managed identity client ID for Workload Identity')
param managedIdentityClientId string

@description('Kubernetes namespace name')
param namespaceName string = 'neo4j'

@description('Service account name')
param serviceAccountName string = 'neo4j-sa'

@description('StatefulSet name')
param statefulSetName string = 'neo4j'

@description('Service name')
param serviceName string = 'neo4j'

@description('LoadBalancer service name')
param loadBalancerServiceName string = 'neo4j-lb'

@description('DNS label prefix for LoadBalancer')
param dnsLabelPrefix string

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

@description('Storage class name')
param storageClassName string

@description('Install Graph Data Science plugin')
param installGraphDataScience bool = false

@description('Install Bloom plugin')
param installBloom bool = false

@description('CPU limit per pod')
param cpuLimit string = '4'

@description('Memory limit per pod')
param memoryLimit string = '16Gi'

// ============================================================================
// MODULE: Namespace
// ============================================================================

module namespace 'namespace.bicep' = {
  name: 'namespace-deployment'
  params: {
    location: location
    aksClusterName: aksClusterName
    aksResourceGroup: aksResourceGroup
    namespaceName: namespaceName
    identityId: identityId
  }
}

// ============================================================================
// MODULE: Service Account
// ============================================================================

module serviceAccount 'serviceaccount.bicep' = {
  name: 'serviceaccount-deployment'
  params: {
    location: location
    aksClusterName: aksClusterName
    aksResourceGroup: aksResourceGroup
    namespaceName: namespaceName
    serviceAccountName: serviceAccountName
    managedIdentityClientId: managedIdentityClientId
    identityId: identityId
  }
  dependsOn: [
    namespace
  ]
}

// ============================================================================
// MODULE: Configuration (ConfigMap and Secret)
// ============================================================================

module configuration 'configuration.bicep' = {
  name: 'configuration-deployment'
  params: {
    location: location
    aksClusterName: aksClusterName
    aksResourceGroup: aksResourceGroup
    namespaceName: namespaceName
    graphDatabaseVersion: graphDatabaseVersion
    adminPassword: adminPassword
    licenseType: licenseType
    nodeCount: replicas
    serviceName: serviceName
    installGraphDataScience: installGraphDataScience
    installBloom: installBloom
    identityId: identityId
  }
  dependsOn: [
    namespace
  ]
}

// ============================================================================
// MODULE: StatefulSet
// ============================================================================

module statefulSet 'statefulset.bicep' = {
  name: 'statefulset-deployment'
  params: {
    location: location
    aksClusterName: aksClusterName
    aksResourceGroup: aksResourceGroup
    namespaceName: namespaceName
    statefulSetName: statefulSetName
    serviceName: serviceName
    serviceAccountName: serviceAccountName
    replicas: replicas
    graphDatabaseVersion: graphDatabaseVersion
    diskSize: diskSize
    storageClassName: storageClassName
    cpuLimit: cpuLimit
    memoryLimit: memoryLimit
    identityId: identityId
  }
  dependsOn: [
    serviceAccount
    configuration
  ]
}

// ============================================================================
// MODULE: Services
// ============================================================================

module services 'services.bicep' = {
  name: 'services-deployment'
  params: {
    location: location
    aksClusterName: aksClusterName
    aksResourceGroup: aksResourceGroup
    namespaceName: namespaceName
    serviceName: serviceName
    loadBalancerServiceName: loadBalancerServiceName
    dnsLabel: dnsLabelPrefix
    identityId: identityId
  }
  dependsOn: [
    statefulSet
  ]
}

// ============================================================================
// OUTPUTS
// ============================================================================

output namespaceName string = namespace.outputs.namespaceName
output serviceAccountName string = serviceAccount.outputs.serviceAccountName
output configMapName string = configuration.outputs.configMapName
output secretName string = configuration.outputs.secretName
output statefulSetName string = statefulSet.outputs.statefulSetName
output serviceName string = services.outputs.serviceName
output loadBalancerServiceName string = services.outputs.loadBalancerServiceName
output externalIp string = services.outputs.externalIp
output neo4jBrowserUrl string = 'http://${services.outputs.externalIp}:7474'
output neo4jBoltUri string = 'neo4j://${services.outputs.externalIp}:7687'
