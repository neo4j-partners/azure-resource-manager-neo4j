// Services Module
// Creates headless service and LoadBalancer service for Neo4j

@description('Azure region for deployment scripts')
param location string

@description('Name of the AKS cluster')
param aksClusterName string

@description('Resource group containing the AKS cluster')
param aksResourceGroup string

@description('Kubernetes namespace')
param namespaceName string

@description('Name for the headless service')
param serviceName string

@description('Name for the LoadBalancer service')
param loadBalancerServiceName string

@description('DNS label for the LoadBalancer service')
param dnsLabel string

@description('Managed identity for deployment script')
param identityId string

// Headless Service YAML
var headlessServiceYaml = '''
apiVersion: v1
kind: Service
metadata:
  name: ${serviceName}
  namespace: ${namespaceName}
  labels:
    app: neo4j
    component: core
spec:
  clusterIP: None
  publishNotReadyAddresses: true
  selector:
    app: neo4j
    component: core
  ports:
  - name: http
    port: 7474
    targetPort: 7474
    protocol: TCP
  - name: https
    port: 7473
    targetPort: 7473
    protocol: TCP
  - name: bolt
    port: 7687
    targetPort: 7687
    protocol: TCP
  - name: cluster-tx
    port: 6000
    targetPort: 6000
    protocol: TCP
  - name: cluster-raft
    port: 7000
    targetPort: 7000
    protocol: TCP
'''

// LoadBalancer Service YAML
var loadBalancerServiceYaml = '''
apiVersion: v1
kind: Service
metadata:
  name: ${loadBalancerServiceName}
  namespace: ${namespaceName}
  labels:
    app: neo4j
    component: core
  annotations:
    service.beta.kubernetes.io/azure-dns-label-name: "${dnsLabel}"
    service.beta.kubernetes.io/azure-load-balancer-health-probe-interval: "10"
spec:
  type: LoadBalancer
  sessionAffinity: ClientIP
  sessionAffinityConfig:
    clientIP:
      timeoutSeconds: 10800
  selector:
    app: neo4j
    component: core
  ports:
  - name: http
    port: 7474
    targetPort: 7474
    protocol: TCP
  - name: bolt
    port: 7687
    targetPort: 7687
    protocol: TCP
'''

// Deployment script to create services
resource createServices 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-services-${uniqueString(resourceGroup().id, namespaceName)}'
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
        name: 'HEADLESS_SERVICE_YAML'
        value: headlessServiceYaml
      }
      {
        name: 'LOADBALANCER_SERVICE_YAML'
        value: loadBalancerServiceYaml
      }
    ]
    scriptContent: '''
      #!/bin/bash
      set -e

      echo "Getting AKS credentials..."
      az aks get-credentials --name $AKS_CLUSTER_NAME --resource-group $AKS_RESOURCE_GROUP --overwrite-existing

      echo "Creating headless service..."
      echo "$HEADLESS_SERVICE_YAML" | kubectl apply -f -

      echo "Creating LoadBalancer service..."
      echo "$LOADBALANCER_SERVICE_YAML" | kubectl apply -f -

      echo "Waiting for services to be created..."
      sleep 5

      echo "Checking services..."
      kubectl get service ${serviceName} -n ${namespaceName}
      kubectl get service ${loadBalancerServiceName} -n ${namespaceName}

      echo "Waiting for LoadBalancer external IP (this may take 2-3 minutes)..."
      for i in {1..60}; do
        EXTERNAL_IP=$(kubectl get service ${loadBalancerServiceName} -n ${namespaceName} -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
        if [ -n "$EXTERNAL_IP" ] && [ "$EXTERNAL_IP" != "<pending>" ]; then
          echo "External IP assigned: $EXTERNAL_IP"
          break
        fi
        echo "Waiting for external IP... ($i/60)"
        sleep 3
      done

      echo "Services created successfully"
    '''
    cleanupPreference: 'OnSuccess'
  }
}

// Query external IP after deployment
resource getExternalIp 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'get-external-ip-${uniqueString(resourceGroup().id, namespaceName)}'
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
    ]
    scriptContent: '''
      #!/bin/bash
      set -e

      echo "Getting AKS credentials..."
      az aks get-credentials --name $AKS_CLUSTER_NAME --resource-group $AKS_RESOURCE_GROUP --overwrite-existing

      echo "Getting external IP..."
      EXTERNAL_IP=$(kubectl get service ${loadBalancerServiceName} -n ${namespaceName} -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")

      echo "External IP: $EXTERNAL_IP"

      # Output as JSON for Bicep to parse
      echo "{\"externalIp\": \"$EXTERNAL_IP\"}" > $AZ_SCRIPTS_OUTPUT_PATH
    '''
    cleanupPreference: 'OnSuccess'
  }
  dependsOn: [
    createServices
  ]
}

// Outputs
output serviceName string = serviceName
output loadBalancerServiceName string = loadBalancerServiceName
output externalIp string = getExternalIp.properties.outputs.externalIp
output deploymentStatus string = createServices.properties.provisioningState
