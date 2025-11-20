// Helm Deployment Module
// Deploys Neo4j using the official Neo4j Helm chart via deploymentScripts
//
// IMPORTANT: This module uses the official Neo4j Helm chart from helm.neo4j.com
// Parameter names must match the chart's values.yaml structure exactly.
// See HELM_PARAMETERS.md for complete parameter reference.
//
// Official Chart: https://github.com/neo4j/helm-charts/tree/master/neo4j
// Documentation: https://neo4j.com/docs/operations-manual/current/kubernetes/

@description('Azure region for deployment scripts')
param location string

@description('Name of the AKS cluster')
param aksClusterName string

@description('Resource group containing the AKS cluster')
param aksResourceGroup string

@description('Kubernetes namespace for Neo4j')
param namespaceName string = 'neo4j'

@description('Helm release name')
param releaseName string = 'neo4j'

@description('Number of Neo4j nodes (1 for standalone, 3+ for cluster)')
@minValue(1)
@maxValue(10)
param nodeCount int

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

@description('CPU request per pod (in millicores)')
param cpuRequest string = '2000m'

@description('Memory request per pod')
param memoryRequest string = '8Gi'

@description('Install Graph Data Science plugin')
param installGraphDataScience bool = false

@description('Install Bloom plugin')
param installBloom bool = false

@description('Managed identity for deployment script')
param identityId string

// ============================================================================
// VARIABLES
// ============================================================================

// Determine cluster mode
var isCluster = nodeCount >= 3
var clusterName = isCluster ? 'neo4j-cluster' : 'neo4j-standalone'

// License agreement value (eval for Evaluation, yes for Enterprise)
var licenseAgreement = licenseType == 'Evaluation' ? 'eval' : 'yes'

// Helm chart configuration
// Pin to specific tested version for reproducible deployments
var helmChartRepo = 'https://helm.neo4j.com/neo4j'
var helmChartName = 'neo4j/neo4j'
var helmChartVersion = '5.26.16'  // Latest stable 5.x version (Nov 2025)

// Storage configuration
var storageClassName = 'neo4j-premium'  // Must match storage.bicep storageClassName
var storageSizeGi = '${diskSize}Gi'

// Calculate memory settings (heap should be ~50% of total memory)
var heapSizeGb = '4G'  // Conservative default for 8Gi total memory
var pageCacheSizeGb = '3G'  // Remaining memory for page cache

// Build plugins list for future use
// Note: Plugins not currently used but prepared for future implementation
var pluginsList = concat(
  installGraphDataScience ? ['graph-data-science'] : [],
  installBloom ? ['bloom'] : []
)
var pluginsEnabled = length(pluginsList) > 0 ? 'true' : 'false'

// ============================================================================
// DEPLOYMENT SCRIPT
// ============================================================================

resource helmInstall 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'helm-install-${uniqueString(resourceGroup().id, namespaceName, releaseName)}'
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
    timeout: 'PT30M'  // 30 minutes for cluster formation
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
        name: 'NAMESPACE_NAME'
        value: namespaceName
      }
      {
        name: 'RELEASE_NAME'
        value: releaseName
      }
      {
        name: 'HELM_CHART_REPO'
        value: helmChartRepo
      }
      {
        name: 'HELM_CHART_NAME'
        value: helmChartName
      }
      {
        name: 'HELM_CHART_VERSION'
        value: helmChartVersion
      }
      {
        name: 'NEO4J_PASSWORD'
        secureValue: adminPassword
      }
      {
        name: 'NEO4J_VERSION'
        value: graphDatabaseVersion
      }
      {
        name: 'LICENSE_AGREEMENT'
        value: licenseAgreement
      }
      {
        name: 'CLUSTER_NAME'
        value: clusterName
      }
      {
        name: 'IS_CLUSTER'
        value: string(isCluster)
      }
      {
        name: 'NODE_COUNT'
        value: string(nodeCount)
      }
      {
        name: 'STORAGE_CLASS'
        value: storageClassName
      }
      {
        name: 'STORAGE_SIZE'
        value: storageSizeGi
      }
      {
        name: 'CPU_REQUEST'
        value: cpuRequest
      }
      {
        name: 'MEMORY_REQUEST'
        value: memoryRequest
      }
      {
        name: 'HEAP_SIZE'
        value: heapSizeGb
      }
      {
        name: 'PAGECACHE_SIZE'
        value: pageCacheSizeGb
      }
      {
        name: 'PLUGINS_ENABLED'
        value: pluginsEnabled
      }
    ]
    scriptContent: '''
      #!/bin/bash
      set -e

      echo "===================================="
      echo "Neo4j Helm Chart Deployment"
      echo "===================================="
      echo "Release: $RELEASE_NAME"
      echo "Namespace: $NAMESPACE_NAME"
      echo "Cluster Mode: $IS_CLUSTER"
      echo "Node Count: $NODE_COUNT"
      echo ""

      # Install kubectl
      echo "Installing kubectl..."
      az aks install-cli

      # Get AKS credentials
      echo "Getting AKS credentials..."
      az aks get-credentials --name $AKS_CLUSTER_NAME --resource-group $AKS_RESOURCE_GROUP --overwrite-existing

      # Install Helm
      echo "Installing Helm..."
      curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

      # Add Neo4j Helm repository
      echo "Adding Neo4j Helm repository..."
      helm repo add neo4j $HELM_CHART_REPO
      helm repo update

      # Create namespace if it doesn't exist
      echo "Creating namespace: $NAMESPACE_NAME"
      kubectl create namespace $NAMESPACE_NAME --dry-run=client -o yaml | kubectl apply -f -

      echo ""
      echo "Installing Neo4j Helm Chart version $HELM_CHART_VERSION..."
      echo ""

      # Build Helm command with corrected parameter names
      HELM_CMD="helm upgrade --install $RELEASE_NAME $HELM_CHART_NAME"
      HELM_CMD="$HELM_CMD --version $HELM_CHART_VERSION"
      HELM_CMD="$HELM_CMD --namespace $NAMESPACE_NAME"
      HELM_CMD="$HELM_CMD --create-namespace"
      HELM_CMD="$HELM_CMD --wait"
      HELM_CMD="$HELM_CMD --timeout 20m"

      # Neo4j core configuration
      # Chart automatically selects correct image based on edition
      HELM_CMD="$HELM_CMD --set neo4j.name=$CLUSTER_NAME"
      HELM_CMD="$HELM_CMD --set neo4j.edition=enterprise"
      HELM_CMD="$HELM_CMD --set neo4j.acceptLicenseAgreement=$LICENSE_AGREEMENT"
      # Password is passed via --set-file to avoid quoting issues with special characters
      echo -n "$NEO4J_PASSWORD" > /tmp/neo4j-password.txt
      HELM_CMD="$HELM_CMD --set-file neo4j.password=/tmp/neo4j-password.txt"

      # Cluster configuration (only if cluster mode)
      if [ "$IS_CLUSTER" == "true" ]; then
        echo "Configuring cluster with $NODE_COUNT nodes..."
        HELM_CMD="$HELM_CMD --set neo4j.minimumClusterSize=$NODE_COUNT"
      else
        echo "Configuring standalone instance..."
      fi

      # Storage configuration
      # CORRECTED: Use volumes.data.dynamic.requests.storage (not just .storage)
      HELM_CMD="$HELM_CMD --set volumes.data.mode=dynamic"
      HELM_CMD="$HELM_CMD --set volumes.data.dynamic.storageClassName=$STORAGE_CLASS"
      HELM_CMD="$HELM_CMD --set volumes.data.dynamic.requests.storage=$STORAGE_SIZE"

      # Resource configuration
      # CORRECTED: Use neo4j.resources.cpu and neo4j.resources.memory
      HELM_CMD="$HELM_CMD --set neo4j.resources.cpu=$CPU_REQUEST"
      HELM_CMD="$HELM_CMD --set neo4j.resources.memory=$MEMORY_REQUEST"

      # Memory configuration (JVM heap and page cache)
      # Use individual --set commands with escaped dots instead of --set-json
      HELM_CMD="$HELM_CMD --set config.server\.memory\.heap\.initial_size=$HEAP_SIZE"
      HELM_CMD="$HELM_CMD --set config.server\.memory\.heap\.max_size=$HEAP_SIZE"
      HELM_CMD="$HELM_CMD --set config.server\.memory\.pagecache\.size=$PAGECACHE_SIZE"

      # Plugin configuration (future - currently not used)
      if [ "$PLUGINS_ENABLED" == "true" ]; then
        echo "Note: Plugin configuration not yet implemented"
        # TODO: Implement plugin installation via env.NEO4JLABS_PLUGINS or init containers
      fi

      # Service configuration (LoadBalancer for Azure external access)
      HELM_CMD="$HELM_CMD --set services.neo4j.enabled=true"
      HELM_CMD="$HELM_CMD --set services.neo4j.spec.type=LoadBalancer"

      # Execute Helm install
      echo ""
      echo "Executing Helm installation..."
      echo "Command: helm upgrade --install $RELEASE_NAME $HELM_CHART_NAME --version $HELM_CHART_VERSION ..."
      echo ""
      eval $HELM_CMD

      # Clean up password file
      rm -f /tmp/neo4j-password.txt

      # Verify deployment
      echo ""
      echo "===================================="
      echo "Verifying Deployment"
      echo "===================================="
      kubectl get pods -n $NAMESPACE_NAME
      echo ""
      kubectl get services -n $NAMESPACE_NAME
      echo ""

      # Wait for LoadBalancer external IP
      echo "Waiting for LoadBalancer external IP..."
      EXTERNAL_IP=""
      for i in {1..60}; do
        EXTERNAL_IP=$(kubectl get service ${RELEASE_NAME} -n $NAMESPACE_NAME -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
        if [ -n "$EXTERNAL_IP" ] && [ "$EXTERNAL_IP" != "null" ]; then
          echo "External IP assigned: $EXTERNAL_IP"
          break
        fi
        echo "Waiting for external IP... ($i/60)"
        sleep 10
      done

      if [ -z "$EXTERNAL_IP" ] || [ "$EXTERNAL_IP" == "null" ]; then
        echo "WARNING: External IP not assigned within timeout"
        EXTERNAL_IP="pending"
      fi

      # Get release status
      RELEASE_STATUS=$(helm status $RELEASE_NAME -n $NAMESPACE_NAME -o json | jq -r '.info.status')
      HELM_VERSION=$(helm list -n $NAMESPACE_NAME -o json | jq -r ".[] | select(.name==\"$RELEASE_NAME\") | .chart")

      echo ""
      echo "===================================="
      echo "Deployment Complete!"
      echo "===================================="
      echo "Release: $RELEASE_NAME"
      echo "Status: $RELEASE_STATUS"
      echo "Chart: $HELM_VERSION"
      echo "External IP: $EXTERNAL_IP"
      echo "Neo4j Browser: http://$EXTERNAL_IP:7474"
      echo "Bolt URI: neo4j://$EXTERNAL_IP:7687"
      echo ""
      echo "Note: It may take 2-3 minutes for Neo4j pods to be fully ready."
      echo ""

      # Save outputs to JSON for Bicep
      cat > $AZ_SCRIPTS_OUTPUT_PATH <<EOF
{
  "releaseName": "$RELEASE_NAME",
  "releaseStatus": "$RELEASE_STATUS",
  "helmVersion": "$HELM_VERSION",
  "externalIp": "$EXTERNAL_IP",
  "browserUrl": "http://$EXTERNAL_IP:7474",
  "boltUri": "neo4j://$EXTERNAL_IP:7687"
}
EOF

      echo "Deployment script completed successfully"
    '''
    cleanupPreference: 'OnSuccess'
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================

output releaseName string = releaseName
output releaseStatus string = helmInstall.properties.outputs.releaseStatus
output helmVersion string = helmInstall.properties.outputs.helmVersion
output externalIp string = helmInstall.properties.outputs.externalIp
output browserUrl string = helmInstall.properties.outputs.browserUrl
output boltUri string = helmInstall.properties.outputs.boltUri
output deploymentStatus string = helmInstall.properties.provisioningState
