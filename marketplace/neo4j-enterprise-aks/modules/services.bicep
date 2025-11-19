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
var headlessServiceYaml = 'apiVersion: v1\nkind: Service\nmetadata:\n  name: ${serviceName}\n  namespace: ${namespaceName}\n  labels:\n    app: neo4j\n    component: core\nspec:\n  clusterIP: None\n  publishNotReadyAddresses: true\n  selector:\n    app: neo4j\n    component: core\n  ports:\n  - name: http\n    port: 7474\n    targetPort: 7474\n    protocol: TCP\n  - name: https\n    port: 7473\n    targetPort: 7473\n    protocol: TCP\n  - name: bolt\n    port: 7687\n    targetPort: 7687\n    protocol: TCP\n  - name: cluster-tx\n    port: 6000\n    targetPort: 6000\n    protocol: TCP\n  - name: cluster-raft\n    port: 7000\n    targetPort: 7000\n    protocol: TCP\n'

// LoadBalancer Service YAML
var loadBalancerServiceYaml = 'apiVersion: v1\nkind: Service\nmetadata:\n  name: ${loadBalancerServiceName}\n  namespace: ${namespaceName}\n  labels:\n    app: neo4j\n    component: core\n  annotations:\n    service.beta.kubernetes.io/azure-dns-label-name: "${dnsLabel}"\n    service.beta.kubernetes.io/azure-load-balancer-health-probe-interval: "10"\nspec:\n  type: LoadBalancer\n  sessionAffinity: ClientIP\n  sessionAffinityConfig:\n    clientIP:\n      timeoutSeconds: 10800\n  selector:\n    app: neo4j\n    component: core\n  ports:\n  - name: http\n    port: 7474\n    targetPort: 7474\n    protocol: TCP\n  - name: bolt\n    port: 7687\n    targetPort: 7687\n    protocol: TCP\n'

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
        name: 'NAMESPACE_NAME'
        value: namespaceName
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

      echo "Installing kubectl..."
      az aks install-cli

      echo "Getting AKS credentials..."
      az aks get-credentials --name $AKS_CLUSTER_NAME --resource-group $AKS_RESOURCE_GROUP --overwrite-existing

      echo "Creating headless service..."
      echo "$HEADLESS_SERVICE_YAML" | kubectl apply -f -

      echo "Creating LoadBalancer service..."
      echo "$LOADBALANCER_SERVICE_YAML" | kubectl apply -f -

      echo "Verifying services..."
      kubectl get service -n $NAMESPACE_NAME

      echo "Services created successfully"
    '''
    cleanupPreference: 'OnSuccess'
  }
}

// Deployment script to get external IP
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
        name: 'LOADBALANCER_SERVICE_NAME'
        value: loadBalancerServiceName
      }
      {
        name: 'NAMESPACE_NAME'
        value: namespaceName
      }
    ]
    scriptContent: '''
      #!/bin/bash
      set -e

      echo "Installing kubectl..."
      az aks install-cli

      echo "Getting AKS credentials..."
      az aks get-credentials --name $AKS_CLUSTER_NAME --resource-group $AKS_RESOURCE_GROUP --overwrite-existing

      echo "Getting external IP..."
      EXTERNAL_IP=$(kubectl get service $LOADBALANCER_SERVICE_NAME -n $NAMESPACE_NAME -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")

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
