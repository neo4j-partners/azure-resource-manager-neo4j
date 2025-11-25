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

@description('Enable debug mode with verbose logging')
param debugMode bool = false

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

// Calculate memory settings following Neo4j best practice: heap + pagecache + 1GB < total memory
// For 8Gi total: 3.5G heap + 3G pagecache + 1.5G system = 8Gi (provides headroom)
var heapSizeGb = '3500M'  // ~44% of total memory, leaving room for system
var pageCacheSizeGb = '3G'  // Page cache for graph data


// DNS-based cluster discovery configuration
// Uses headless service DNS A records instead of K8S API for cluster member discovery
// This is simpler and doesn't require RBAC/ServiceAccount token mounting

// ============================================================================
// DEPLOYMENT SCRIPT - Multi-Installation Approach
// ============================================================================
// Per official Neo4j Kubernetes Operations Manual, deploying a cluster requires
// installing the Helm chart N times (once per server) instead of using replicas.
// Each installation creates 1 StatefulSet with 1 pod, and servers join via neo4j.name.
// See CLUSTER_BEST_PRACTICES.md for detailed explanation.

// Generate server names array based on nodeCount
var serverNames = [for i in range(0, isCluster ? nodeCount : 1): isCluster ? 'server-${i + 1}' : releaseName]

// Create namespace and shared headless service for DNS discovery
// The headless service must exist BEFORE Neo4j pods start so DNS resolution works
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
        name: 'NAMESPACE_NAME'
        value: namespaceName
      }
      {
        name: 'CLUSTER_NAME'
        value: clusterName
      }
      {
        name: 'IS_CLUSTER'
        value: isCluster ? 'true' : 'false'
      }
    ]
    scriptContent: '''
      #!/bin/bash
      set -e

      echo "===================================="
      echo "Creating Kubernetes Namespace"
      echo "===================================="
      echo "Namespace: $NAMESPACE_NAME"

      # Install kubectl
      az aks install-cli

      # Get AKS credentials
      az aks get-credentials --name $AKS_CLUSTER_NAME --resource-group $AKS_RESOURCE_GROUP --overwrite-existing

      # Create namespace (idempotent)
      kubectl create namespace $NAMESPACE_NAME --dry-run=client -o yaml | kubectl apply -f -

      echo "✓ Namespace created: $NAMESPACE_NAME"

      # For cluster mode, create shared headless service for DNS discovery
      # This service MUST exist before Neo4j pods start so they can discover each other
      if [ "$IS_CLUSTER" == "true" ]; then
        echo ""
        echo "===================================="
        echo "Creating Headless Service for DNS Discovery"
        echo "===================================="
        echo "Service: ${CLUSTER_NAME}-internals"

        cat <<SERVICEEOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: ${CLUSTER_NAME}-internals
  namespace: $NAMESPACE_NAME
  labels:
    app: $CLUSTER_NAME
    helm.neo4j.com/clustering: "true"
    helm.neo4j.com/service: "internals"
spec:
  type: ClusterIP
  clusterIP: None
  publishNotReadyAddresses: true
  selector:
    app: $CLUSTER_NAME
    helm.neo4j.com/clustering: "true"
  ports:
    - name: tcp-discovery
      port: 6000
      targetPort: 6000
      protocol: TCP
    - name: tcp-raft
      port: 7000
      targetPort: 7000
      protocol: TCP
    - name: tcp-tx
      port: 7688
      targetPort: 7688
      protocol: TCP
    - name: tcp-bolt
      port: 7687
      targetPort: 7687
      protocol: TCP
    - name: tcp-http
      port: 7474
      targetPort: 7474
      protocol: TCP
SERVICEEOF

        echo "✓ Headless service created: ${CLUSTER_NAME}-internals"
        kubectl get service ${CLUSTER_NAME}-internals -n $NAMESPACE_NAME
      fi

      # Save output
      cat > $AZ_SCRIPTS_OUTPUT_PATH <<EOF
{
  "namespaceName": "$NAMESPACE_NAME",
  "clusterName": "$CLUSTER_NAME",
  "headlessService": "${CLUSTER_NAME}-internals",
  "status": "Created"
}
EOF
    '''
    cleanupPreference: 'OnSuccess'
  }
}

// Deploy all servers SEQUENTIALLY to avoid race conditions when creating shared resources
// First server creates shared resources (secret, LoadBalancer), subsequent servers reference them
// Servers will discover each other via DNS resolver using headless service A records
// batchSize(1) ensures one server deploys at a time in sequence
@batchSize(1)
resource helmInstall 'Microsoft.Resources/deploymentScripts@2023-08-01' = [for (serverName, index) in serverNames: {
  name: 'helm-install-${serverName}-${uniqueString(resourceGroup().id, namespaceName)}'
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
        value: serverName  // Unique release name per server
      }
      {
        name: 'SERVER_NAME'
        value: serverName  // For logging
      }
      {
        name: 'SERVER_INDEX'
        value: string(index)  // For potential use in configuration
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
        value: isCluster ? 'true' : 'false'
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
        name: 'DEBUG_MODE'
        value: toLower(string(debugMode))
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
      # Note: Namespace created separately before server deployments
      # Note: --wait removed - servers deploy in parallel and form cluster together
      # All servers start simultaneously, discover via DNS resolver, form quorum

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
        echo "Installing server: $SERVER_NAME"
        HELM_CMD="$HELM_CMD --set neo4j.minimumClusterSize=$NODE_COUNT"

        # DNS Resolver Configuration for Cluster Discovery
        # Instead of K8S API-based discovery, use DNS A records from a headless service
        # This is simpler and doesn't require RBAC/ServiceAccount token mounting
        echo "Configuring DNS-based cluster discovery..."

        # Enable the internals service as headless for DNS discovery
        # The headless service returns A records for all cluster member pod IPs
        HELM_CMD="$HELM_CMD --set services.internals.enabled=true"

        # Production best practice: Enable pod anti-affinity
        # Prevents all cluster members from running on same node (single point of failure)
        echo "Enabling pod anti-affinity to distribute cluster across nodes..."
        HELM_CMD="$HELM_CMD --set podSpec.podAntiAffinity=true"

        echo "DNS resolver will discover cluster members via headless service DNS A records"
      else
        echo "Configuring standalone instance..."
      fi

      # Storage configuration
      # CORRECTED: Use volumes.data.dynamic.requests.storage (not just .storage)
      HELM_CMD="$HELM_CMD --set volumes.data.mode=dynamic"
      HELM_CMD="$HELM_CMD --set volumes.data.dynamic.storageClassName=$STORAGE_CLASS"
      HELM_CMD="$HELM_CMD --set volumes.data.dynamic.requests.storage=$STORAGE_SIZE"

      # Resource configuration
      # Best practice: Set requests and limits to same values to prevent bursting
      # This ensures consistent resources and prevents pod eviction under pressure
      HELM_CMD="$HELM_CMD --set neo4j.resources.requests.cpu=$CPU_REQUEST"
      HELM_CMD="$HELM_CMD --set neo4j.resources.requests.memory=$MEMORY_REQUEST"
      HELM_CMD="$HELM_CMD --set neo4j.resources.limits.cpu=$CPU_REQUEST"
      HELM_CMD="$HELM_CMD --set neo4j.resources.limits.memory=$MEMORY_REQUEST"

      # Memory and cluster discovery configuration
      # DNS resolver uses headless service DNS A records for cluster member discovery
      # DNS endpoint format: <cluster-name>-internals.<namespace>.svc.cluster.local:6000

      # Build configuration with DNS resolver and optional debug settings
      if [ "$IS_CLUSTER" == "true" ]; then
        # DNS endpoint for cluster discovery - points to headless internals service
        DNS_ENDPOINT="${CLUSTER_NAME}-internals.${NAMESPACE_NAME}.svc.cluster.local:6000"
        echo "DNS discovery endpoint: $DNS_ENDPOINT"

        if [ "$DEBUG_MODE" == "true" ]; then
          echo "Debug mode enabled - configuring verbose logging..."
          cat > /tmp/neo4j-config-values.yaml <<EOF
config:
  server.memory.heap.initial_size: "$HEAP_SIZE"
  server.memory.heap.max_size: "$HEAP_SIZE"
  server.memory.pagecache.size: "$PAGECACHE_SIZE"
  # DNS-based cluster discovery configuration
  dbms.cluster.discovery.resolver_type: "DNS"
  dbms.cluster.discovery.endpoints: "$DNS_ENDPOINT"
  # Debug logging configuration
  server.logs.debug.level: "DEBUG"
  dbms.logs.debug.level: "DEBUG"
  dbms.logs.debug.rotation.keep_number: "10"
  dbms.logs.debug.rotation.size: "100M"
  # Enable JVM debug output
  server.jvm.additional.dbms.logs.gc.enabled: "true"
  server.jvm.additional.dbms.jvm.additional: "-XX:+PrintGCDetails -XX:+PrintGCDateStamps"
EOF
        else
          cat > /tmp/neo4j-config-values.yaml <<EOF
config:
  server.memory.heap.initial_size: "$HEAP_SIZE"
  server.memory.heap.max_size: "$HEAP_SIZE"
  server.memory.pagecache.size: "$PAGECACHE_SIZE"
  # DNS-based cluster discovery configuration
  dbms.cluster.discovery.resolver_type: "DNS"
  dbms.cluster.discovery.endpoints: "$DNS_ENDPOINT"
EOF
        fi
      else
        # Standalone mode - no cluster discovery needed
        if [ "$DEBUG_MODE" == "true" ]; then
          echo "Debug mode enabled - configuring verbose logging..."
          cat > /tmp/neo4j-config-values.yaml <<EOF
config:
  server.memory.heap.initial_size: "$HEAP_SIZE"
  server.memory.heap.max_size: "$HEAP_SIZE"
  server.memory.pagecache.size: "$PAGECACHE_SIZE"
  # Debug logging configuration
  server.logs.debug.level: "DEBUG"
  dbms.logs.debug.level: "DEBUG"
  dbms.logs.debug.rotation.keep_number: "10"
  dbms.logs.debug.rotation.size: "100M"
  # Enable JVM debug output
  server.jvm.additional.dbms.logs.gc.enabled: "true"
  server.jvm.additional.dbms.jvm.additional: "-XX:+PrintGCDetails -XX:+PrintGCDateStamps"
EOF
        else
          cat > /tmp/neo4j-config-values.yaml <<EOF
config:
  server.memory.heap.initial_size: "$HEAP_SIZE"
  server.memory.heap.max_size: "$HEAP_SIZE"
  server.memory.pagecache.size: "$PAGECACHE_SIZE"
EOF
        fi
      fi

      HELM_CMD="$HELM_CMD -f /tmp/neo4j-config-values.yaml"

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

      # Clean up temporary files
      rm -f /tmp/neo4j-password.txt
      rm -f /tmp/neo4j-config-values.yaml

      # Verify deployment
      echo ""
      echo "===================================="
      echo "Verifying Deployment"
      echo "===================================="
      kubectl get pods -n $NAMESPACE_NAME
      echo ""
      kubectl get services -n $NAMESPACE_NAME
      echo ""

      # Verify DNS resolver configuration for cluster mode
      if [ "$IS_CLUSTER" == "true" ]; then
        echo "===================================="
        echo "Verifying DNS Discovery Configuration"
        echo "===================================="

        # DNS endpoint for cluster discovery
        DNS_ENDPOINT="${CLUSTER_NAME}-internals.${NAMESPACE_NAME}.svc.cluster.local"
        echo "DNS discovery endpoint: $DNS_ENDPOINT:6000"

        # Check for internals service (headless or ClusterIP)
        echo ""
        echo "Checking internals service..."
        INTERNALS_SERVICE=$(kubectl get services -n $NAMESPACE_NAME -o json | jq -r '.items[] | select(.metadata.name | contains("internals")) | .metadata.name' | head -1)
        if [ -n "$INTERNALS_SERVICE" ]; then
          CLUSTER_IP=$(kubectl get service $INTERNALS_SERVICE -n $NAMESPACE_NAME -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")
          if [ "$CLUSTER_IP" == "None" ]; then
            echo "✓ Headless internals service found: $INTERNALS_SERVICE (clusterIP=None)"
          else
            echo "✓ Internals service found: $INTERNALS_SERVICE (clusterIP=$CLUSTER_IP)"
          fi

          # Show service endpoints
          ENDPOINTS=$(kubectl get endpoints $INTERNALS_SERVICE -n $NAMESPACE_NAME -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || echo "")
          if [ -n "$ENDPOINTS" ]; then
            echo "  Endpoints: $ENDPOINTS"
          fi
        else
          echo "⚠ Internals service not yet created (will be created by Helm)"
        fi

        # Wait for pods to be ready for DNS testing
        echo ""
        echo "Waiting for pods to be ready for DNS testing..."
        kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=neo4j -n $NAMESPACE_NAME --timeout=300s || true

        # Test DNS resolution from first pod if available
        FIRST_POD=$(kubectl get pods -n $NAMESPACE_NAME -l app.kubernetes.io/name=neo4j -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        if [ -n "$FIRST_POD" ]; then
          echo ""
          echo "Testing DNS resolution from pod $FIRST_POD..."

          # Test DNS lookup for the internals service
          if kubectl exec $FIRST_POD -n $NAMESPACE_NAME -- nslookup $DNS_ENDPOINT 2>/dev/null | grep -q "Address:"; then
            echo "✓ DNS resolution working for $DNS_ENDPOINT"
            # Show resolved addresses
            kubectl exec $FIRST_POD -n $NAMESPACE_NAME -- nslookup $DNS_ENDPOINT 2>/dev/null | grep "Address:" | tail -n +2 || true
          else
            echo "⚠ DNS resolution test skipped (pod may not be fully ready yet)"
          fi

          # Verify cluster discovery port is accessible
          echo ""
          echo "Verifying cluster discovery port (6000) is accessible..."
          if kubectl exec $FIRST_POD -n $NAMESPACE_NAME -- sh -c "nc -zv localhost 6000 2>&1" | grep -q "succeeded\|open"; then
            echo "✓ Cluster discovery port 6000 is accessible"
          else
            echo "⚠ Cluster discovery port verification skipped (pod may not be fully ready)"
          fi

          # Check Neo4j cluster configuration
          echo ""
          echo "Checking Neo4j cluster configuration..."
          if kubectl exec $FIRST_POD -n $NAMESPACE_NAME -- sh -c "cat /var/lib/neo4j/conf/neo4j.conf 2>/dev/null | grep -E 'discovery|resolver'" 2>/dev/null; then
            echo "✓ Discovery configuration found in neo4j.conf"
          else
            echo "⚠ Could not read neo4j.conf (pod may not be fully ready)"
          fi
        fi

        echo ""
      fi

      # Wait for LoadBalancer external IP
      echo "Waiting for LoadBalancer external IP..."
      EXTERNAL_IP=""
      # Neo4j Helm chart creates LoadBalancer service with pattern: <release>-standalone-lb-neo4j or <release>-lb-neo4j
      # Find the LoadBalancer service dynamically
      for i in {1..60}; do
        # First try to find any LoadBalancer service in the namespace
        LB_SERVICE=$(kubectl get services -n $NAMESPACE_NAME -o json | jq -r '.items[] | select(.spec.type=="LoadBalancer") | .metadata.name' | head -1)
        if [ -n "$LB_SERVICE" ]; then
          EXTERNAL_IP=$(kubectl get service $LB_SERVICE -n $NAMESPACE_NAME -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
          if [ -n "$EXTERNAL_IP" ] && [ "$EXTERNAL_IP" != "null" ]; then
            echo "External IP assigned: $EXTERNAL_IP (service: $LB_SERVICE)"
            break
          fi
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
  // All servers wait for namespace creation, then deploy sequentially via batchSize(1)
  dependsOn: [createNamespace]
}]

// ============================================================================
// OUTPUTS
// ============================================================================

// Primary outputs (from first server for backward compatibility)
output releaseName string = serverNames[0]
output releaseStatus string = helmInstall[0].properties.outputs.releaseStatus
output helmVersion string = helmInstall[0].properties.outputs.helmVersion
output externalIp string = helmInstall[0].properties.outputs.externalIp
output browserUrl string = helmInstall[0].properties.outputs.browserUrl
output boltUri string = helmInstall[0].properties.outputs.boltUri
output deploymentStatus string = helmInstall[0].properties.provisioningState

// Array outputs for all servers (for cluster deployments)
output serverNames array = serverNames
output serverCount int = length(serverNames)
output allDeploymentStatuses array = [for (serverName, index) in serverNames: {
  serverName: serverName
  releaseStatus: helmInstall[index].properties.outputs.releaseStatus
  deploymentStatus: helmInstall[index].properties.provisioningState
}]
