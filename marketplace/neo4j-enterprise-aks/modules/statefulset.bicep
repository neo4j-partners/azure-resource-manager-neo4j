// StatefulSet Module
// Creates Neo4j StatefulSet with persistent storage

@description('Azure region for deployment scripts')
param location string

@description('Name of the AKS cluster')
param aksClusterName string

@description('Resource group containing the AKS cluster')
param aksResourceGroup string

@description('Kubernetes namespace')
param namespaceName string

@description('Name for the StatefulSet')
param statefulSetName string

@description('Service name for headless service')
param serviceName string

@description('Service account name')
param serviceAccountName string

@description('Number of Neo4j replicas')
param replicas int

@description('Neo4j graph database version')
param graphDatabaseVersion string

@description('Size of data disk per pod in GB')
param diskSize int

@description('Storage class name')
param storageClassName string

@description('CPU request and limit')
param cpuLimit string = '4'

@description('Memory request and limit')
param memoryLimit string = '16Gi'

@description('Managed identity for deployment script')
param identityId string

// Determine container image
var neo4jImage = graphDatabaseVersion == '5' ? 'neo4j:5-enterprise' : 'neo4j:4.4-enterprise'

// StatefulSet YAML
var statefulSetYaml = 'apiVersion: apps/v1\nkind: StatefulSet\nmetadata:\n  name: ${statefulSetName}\n  namespace: ${namespaceName}\n  labels:\n    app: neo4j\n    component: core\nspec:\n  serviceName: ${serviceName}\n  replicas: ${replicas}\n  selector:\n    matchLabels:\n      app: neo4j\n      component: core\n  template:\n    metadata:\n      labels:\n        app: neo4j\n        component: core\n        azure.workload.identity/use: "true"\n    spec:\n      serviceAccountName: ${serviceAccountName}\n      securityContext:\n        fsGroup: 7474\n        runAsUser: 7474\n        runAsGroup: 7474\n        runAsNonRoot: true\n      initContainers:\n      - name: init-data-dir\n        image: busybox:latest\n        command:\n        - sh\n        - -c\n        - |\n          echo "Initializing data directory..."\n          mkdir -p /data /logs\n          chown -R 7474:7474 /data /logs\n          chmod 755 /data /logs\n          echo "Data directory initialized"\n        volumeMounts:\n        - name: data\n          mountPath: /data\n        - name: logs\n          mountPath: /logs\n        securityContext:\n          runAsUser: 0\n      containers:\n      - name: neo4j\n        image: ${neo4jImage}\n        imagePullPolicy: IfNotPresent\n        ports:\n        - containerPort: 7474\n          name: http\n        - containerPort: 7473\n          name: https\n        - containerPort: 7687\n          name: bolt\n        - containerPort: 6000\n          name: cluster-tx\n        - containerPort: 7000\n          name: cluster-raft\n        env:\n        - name: POD_NAME\n          valueFrom:\n            fieldRef:\n              fieldPath: metadata.name\n        - name: POD_NAMESPACE\n          valueFrom:\n            fieldRef:\n              fieldPath: metadata.namespace\n        envFrom:\n        - configMapRef:\n            name: neo4j-config\n        - secretRef:\n            name: neo4j-auth\n        volumeMounts:\n        - name: data\n          mountPath: /data\n        - name: logs\n          mountPath: /logs\n        resources:\n          requests:\n            cpu: "${cpuLimit}"\n            memory: "${memoryLimit}"\n          limits:\n            cpu: "${cpuLimit}"\n            memory: "${memoryLimit}"\n        livenessProbe:\n          httpGet:\n            path: /\n            port: 7474\n          initialDelaySeconds: 300\n          periodSeconds: 10\n          timeoutSeconds: 5\n          failureThreshold: 3\n        readinessProbe:\n          tcpSocket:\n            port: 7687\n          initialDelaySeconds: 30\n          periodSeconds: 10\n          timeoutSeconds: 5\n          failureThreshold: 3\n      volumes:\n      - name: logs\n        emptyDir: {}\n  volumeClaimTemplates:\n  - metadata:\n      name: data\n    spec:\n      accessModes:\n      - ReadWriteOnce\n      storageClassName: ${storageClassName}\n      resources:\n        requests:\n          storage: ${diskSize}Gi\n'

// Deployment script to create StatefulSet
resource createStatefulSet 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-statefulset-${uniqueString(resourceGroup().id, namespaceName)}'
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
        name: 'STATEFULSET_YAML'
        value: statefulSetYaml
      }
    ]
    scriptContent: '''
      #!/bin/bash
      set -e

      echo "Installing kubectl..."
      az aks install-cli

      echo "Getting AKS credentials..."
      az aks get-credentials --name $AKS_CLUSTER_NAME --resource-group $AKS_RESOURCE_GROUP --overwrite-existing

      echo "Creating StatefulSet..."
      echo "$STATEFULSET_YAML" | kubectl apply -f -

      echo "Verifying StatefulSet..."
      kubectl get statefulset ${statefulSetName} -n ${namespaceName}

      echo "StatefulSet created successfully"
    '''
    cleanupPreference: 'OnSuccess'
  }
}

// Outputs
output statefulSetName string = statefulSetName
output deploymentStatus string = createStatefulSet.properties.provisioningState
