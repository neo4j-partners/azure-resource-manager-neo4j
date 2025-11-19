// Configuration Module
// Creates ConfigMap and Secret for Neo4j configuration

@description('Azure region for deployment scripts')
param location string

@description('Name of the AKS cluster')
param aksClusterName string

@description('Resource group containing the AKS cluster')
param aksResourceGroup string

@description('Kubernetes namespace')
param namespaceName string

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

@description('Number of Neo4j nodes (1 for standalone, 3+ for cluster)')
param nodeCount int

@description('Service name for Neo4j (used for DNS)')
param serviceName string

@description('Install Graph Data Science plugin')
param installGraphDataScience bool = false

@description('Install Bloom plugin')
param installBloom bool = false

@description('Managed identity for deployment script')
param identityId string

// Determine if cluster mode
var isCluster = nodeCount >= 3

// License agreement value
var licenseAgreement = licenseType == 'Evaluation' ? 'eval' : 'yes'

// Build discovery endpoints for cluster
var discoveryEndpointsList = [for i in range(0, nodeCount): '${serviceName}-${i}.${serviceName}.${namespaceName}.svc.cluster.local:6000']
var discoveryEndpoints = isCluster ? join(discoveryEndpointsList, ',') : ''

// Base configuration for all deployments
var baseConfig = '''
apiVersion: v1
kind: ConfigMap
metadata:
  name: neo4j-config
  namespace: ${namespaceName}
data:
  NEO4J_EDITION: "enterprise"
  NEO4J_ACCEPT_LICENSE_AGREEMENT: "${licenseAgreement}"
  NEO4J_server_default__listen__address: "0.0.0.0"
  NEO4J_server_bolt_advertised__address: ":7687"
  NEO4J_server_http_advertised__address: ":7474"
  NEO4J_server_https_advertised__address: ":7473"
  NEO4J_dbms_security_auth__enabled: "true"
  NEO4J_server_directories_data: "/data"
  NEO4J_server_directories_logs: "/logs"
  NEO4J_server_memory_heap_initial__size: "2G"
  NEO4J_server_memory_heap_max__size: "2G"
  NEO4J_server_memory_pagecache_size: "4G"
  NEO4J_dbms_default__database: "neo4j"
'''

// Cluster-specific configuration
var clusterConfig = '''
  NEO4J_server_cluster_system__database__mode: "PRIMARY"
  NEO4J_server_discovery_v2_endpoints: "${discoveryEndpoints}"
  NEO4J_initial_server_mode__constraint: "PRIMARY"
'''

// Combine base and cluster config if needed
var configMapYaml = isCluster ? '${baseConfig}${clusterConfig}' : baseConfig

// Secret YAML
var secretYaml = '''
apiVersion: v1
kind: Secret
metadata:
  name: neo4j-auth
  namespace: ${namespaceName}
type: Opaque
stringData:
  NEO4J_AUTH: "neo4j/${adminPassword}"
'''

// Deployment script to create ConfigMap and Secret
resource createConfiguration 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-config-${uniqueString(resourceGroup().id, namespaceName)}'
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
        name: 'CONFIGMAP_YAML'
        value: configMapYaml
      }
      {
        name: 'SECRET_YAML'
        value: secretYaml
      }
    ]
    scriptContent: '''
      #!/bin/bash
      set -e

      echo "Getting AKS credentials..."
      az aks get-credentials --name $AKS_CLUSTER_NAME --resource-group $AKS_RESOURCE_GROUP --overwrite-existing

      echo "Creating ConfigMap..."
      echo "$CONFIGMAP_YAML" | kubectl apply -f -

      echo "Creating Secret..."
      echo "$SECRET_YAML" | kubectl apply -f -

      echo "Verifying resources..."
      kubectl get configmap neo4j-config -n ${namespaceName}
      kubectl get secret neo4j-auth -n ${namespaceName}

      echo "Configuration created successfully"
    '''
    cleanupPreference: 'OnSuccess'
  }
}

// Outputs
output configMapName string = 'neo4j-config'
output secretName string = 'neo4j-auth'
output deploymentStatus string = createConfiguration.properties.provisioningState
