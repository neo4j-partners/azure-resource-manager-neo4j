// Helm Deployment Module
// Deploys Neo4j using the official Neo4j Helm chart via deploymentScripts

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

// Determine cluster mode
var isCluster = nodeCount >= 3
var minClusterSize = isCluster ? nodeCount : 1

// License agreement value
var licenseAgreement = licenseType == 'Evaluation' ? 'eval' : 'yes'

// Build plugins array
var plugins = concat(
  installGraphDataScience ? ['graph-data-science'] : [],
  installBloom ? ['bloom'] : []
)
var pluginsJson = length(plugins) > 0 ? '["${join(plugins, '","')}"]' : '[]'

// Helm chart configuration
var helmChartRepo = 'https://helm.neo4j.com/neo4j'
var helmChartName = 'neo4j/neo4j'
var helmChartVersion = '' // Use latest 5.x compatible version

// Storage configuration
var storageClassName = 'neo4j-premium'  // Must match storage.bicep storageClassName
var storageSizeGi = '${diskSize}Gi'

// Deployment script to install Helm chart
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
        name: 'MIN_CLUSTER_SIZE'
        value: string(minClusterSize)
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
        name: 'PLUGINS'
        value: pluginsJson
      }
    ]
    scriptContent: '''
      #!/bin/bash
      set -e

      echo "===================================="
      echo "Neo4j Helm Chart Deployment"
      echo "===================================="

      # Install kubectl
      echo "Installing kubectl..."
      az aks install-cli

      # Get AKS credentials
      echo "Getting AKS credentials..."
      az aks get-credentials --name $AKS_CLUSTER_NAME --resource-group $AKS_RESOURCE_GROUP --overwrite-existing

      # Install Helm
      echo "Installing Helm..."
      curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

      # Add Neo4j Helm repository
      echo "Adding Neo4j Helm repository..."
      helm repo add neo4j $HELM_CHART_REPO
      helm repo update

      # Create namespace if it doesn't exist
      echo "Creating namespace: $NAMESPACE_NAME"
      kubectl create namespace $NAMESPACE_NAME --dry-run=client -o yaml | kubectl apply -f -

      # Prepare Helm values
      echo "Preparing Helm values..."

      # Install or upgrade Neo4j
      echo "Installing Neo4j via Helm..."
      echo "  Release: $RELEASE_NAME"
      echo "  Namespace: $NAMESPACE_NAME"
      echo "  Version: $NEO4J_VERSION"
      echo "  Cluster Size: $MIN_CLUSTER_SIZE"
      echo "  Storage: $STORAGE_SIZE"

      HELM_CMD="helm upgrade --install $RELEASE_NAME $HELM_CHART_NAME"
      HELM_CMD="$HELM_CMD --namespace $NAMESPACE_NAME"
      HELM_CMD="$HELM_CMD --create-namespace"
      HELM_CMD="$HELM_CMD --wait"
      HELM_CMD="$HELM_CMD --timeout 20m"

      # Version and edition
      HELM_CMD="$HELM_CMD --set image.repository=neo4j"
      HELM_CMD="$HELM_CMD --set-string image.tag=$NEO4J_VERSION"
      HELM_CMD="$HELM_CMD --set neo4j.edition=enterprise"
      HELM_CMD="$HELM_CMD --set neo4j.acceptLicenseAgreement=$LICENSE_AGREEMENT"
      HELM_CMD="$HELM_CMD --set neo4j.password=$NEO4J_PASSWORD"

      # Cluster configuration
      if [ "$MIN_CLUSTER_SIZE" -gt 1 ]; then
        echo "Configuring cluster mode with $MIN_CLUSTER_SIZE nodes..."
        HELM_CMD="$HELM_CMD --set neo4j.minimumClusterSize=$MIN_CLUSTER_SIZE"
        HELM_CMD="$HELM_CMD --set neo4j.name=neo4j-cluster"
      else
        echo "Configuring standalone mode..."
        HELM_CMD="$HELM_CMD --set neo4j.name=neo4j-standalone"
      fi

      # Storage configuration
      HELM_CMD="$HELM_CMD --set volumes.data.mode=dynamic"
      HELM_CMD="$HELM_CMD --set volumes.data.dynamic.storageClassName=$STORAGE_CLASS"
      HELM_CMD="$HELM_CMD --set-string volumes.data.dynamic.storage=$STORAGE_SIZE"

      # Resource configuration
      HELM_CMD="$HELM_CMD --set-string resources.cpu=$CPU_REQUEST"
      HELM_CMD="$HELM_CMD --set-string resources.memory=$MEMORY_REQUEST"

      # Memory configuration (explicit JVM settings)
      # Use --set-json to create flat keys with dots, not nested structures
      HELM_CMD="$HELM_CMD --set-json config='{\"server.memory.heap.initial_size\":\"4G\",\"server.memory.heap.max_size\":\"4G\",\"server.memory.pagecache.size\":\"3G\"}'"

      # Plugin configuration
      if [ "$PLUGINS" != "[]" ]; then
        echo "Enabling plugins: $PLUGINS"
        HELM_CMD="$HELM_CMD --set-json config.NEO4J_PLUGINS='$PLUGINS'"
      fi

      # Service configuration (LoadBalancer for Azure)
      HELM_CMD="$HELM_CMD --set services.neo4j.enabled=true"
      HELM_CMD="$HELM_CMD --set services.neo4j.type=LoadBalancer"

      # Execute Helm install
      echo "Executing: $HELM_CMD"
      eval $HELM_CMD

      # Verify deployment
      echo ""
      echo "Verifying deployment..."
      kubectl get pods -n $NAMESPACE_NAME
      kubectl get services -n $NAMESPACE_NAME

      # Get service details
      echo ""
      echo "Waiting for LoadBalancer external IP..."
      for i in {1..60}; do
        EXTERNAL_IP=$(kubectl get service ${RELEASE_NAME} -n $NAMESPACE_NAME -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
        if [ -n "$EXTERNAL_IP" ] && [ "$EXTERNAL_IP" != "null" ]; then
          echo "External IP assigned: $EXTERNAL_IP"
          break
        fi
        echo "Waiting for external IP... ($i/60)"
        sleep 10
      done

      # Output results
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

      # Save outputs to JSON
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

// Outputs
output releaseName string = releaseName
output releaseStatus string = helmInstall.properties.outputs.releaseStatus
output helmVersion string = helmInstall.properties.outputs.helmVersion
output externalIp string = helmInstall.properties.outputs.externalIp
output browserUrl string = helmInstall.properties.outputs.browserUrl
output boltUri string = helmInstall.properties.outputs.boltUri
output deploymentStatus string = helmInstall.properties.provisioningState
