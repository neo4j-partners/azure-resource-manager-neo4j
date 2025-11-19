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
var statefulSetYaml = '''
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: ${statefulSetName}
  namespace: ${namespaceName}
  labels:
    app: neo4j
    component: core
spec:
  serviceName: ${serviceName}
  replicas: ${replicas}
  selector:
    matchLabels:
      app: neo4j
      component: core
  template:
    metadata:
      labels:
        app: neo4j
        component: core
        azure.workload.identity/use: "true"
    spec:
      serviceAccountName: ${serviceAccountName}
      securityContext:
        fsGroup: 7474
        runAsUser: 7474
        runAsGroup: 7474
        runAsNonRoot: true
      initContainers:
      - name: init-data-dir
        image: busybox:latest
        command:
        - sh
        - -c
        - |
          echo "Initializing data directory..."
          mkdir -p /data /logs
          chown -R 7474:7474 /data /logs
          chmod 755 /data /logs
          echo "Data directory initialized"
        volumeMounts:
        - name: data
          mountPath: /data
        - name: logs
          mountPath: /logs
        securityContext:
          runAsUser: 0
      containers:
      - name: neo4j
        image: ${neo4jImage}
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 7474
          name: http
        - containerPort: 7473
          name: https
        - containerPort: 7687
          name: bolt
        - containerPort: 6000
          name: cluster-tx
        - containerPort: 7000
          name: cluster-raft
        env:
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: POD_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        envFrom:
        - configMapRef:
            name: neo4j-config
        - secretRef:
            name: neo4j-auth
        volumeMounts:
        - name: data
          mountPath: /data
        - name: logs
          mountPath: /logs
        resources:
          requests:
            cpu: "${cpuLimit}"
            memory: "${memoryLimit}"
          limits:
            cpu: "${cpuLimit}"
            memory: "${memoryLimit}"
        livenessProbe:
          httpGet:
            path: /
            port: 7474
          initialDelaySeconds: 300
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        readinessProbe:
          tcpSocket:
            port: 7687
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
      volumes:
      - name: logs
        emptyDir: {}
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes:
      - ReadWriteOnce
      storageClassName: ${storageClassName}
      resources:
        requests:
          storage: ${diskSize}Gi
'''

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
