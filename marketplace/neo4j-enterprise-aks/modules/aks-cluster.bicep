// AKS Cluster Module
// Creates AKS cluster with system and user node pools, monitoring, and Workload Identity

@description('Azure region for all resources')
param location string

@description('Name for the AKS cluster')
param clusterName string

@description('Kubernetes version')
param kubernetesVersion string = '1.31'

@description('Resource ID of the system subnet')
param systemSubnetId string

@description('Resource ID of the user subnet')
param userSubnetId string

@description('Resource ID of the managed identity')
param identityId string

@description('Principal ID of the managed identity')
param identityPrincipalId string

@description('VM size for system node pool')
param systemNodeSize string = 'Standard_D2s_v5'

@description('VM size for user node pool')
param userNodeSize string = 'Standard_E4s_v5'

@description('Minimum node count for user node pool')
param userNodeCountMin int = 1

@description('Maximum node count for user node pool')
param userNodeCountMax int = 10

@description('Initial node count for user node pool')
param userNodeCount int = 1

@description('Tags to apply to all resources')
param tags object = {}

// Built-in Azure role definitions (GUIDs are constant across all subscriptions)
var aksClusterUserRoleId = '4abbcc35-e782-43d8-92c5-2d3f1bd2253f' // Azure Kubernetes Service Cluster User Role

// Log Analytics Workspace for monitoring
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: '${clusterName}-logs'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// AKS Cluster
resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-02-01' = {
  name: clusterName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identityId}': {}
    }
  }
  properties: {
    kubernetesVersion: kubernetesVersion
    dnsPrefix: '${clusterName}-dns'

    // Enable Workload Identity and OIDC issuer
    oidcIssuerProfile: {
      enabled: true
    }
    securityProfile: {
      workloadIdentity: {
        enabled: true
      }
    }

    // Agent pools configuration
    agentPoolProfiles: [
      {
        name: 'system'
        count: 3
        vmSize: systemNodeSize
        osType: 'Linux'
        osSKU: 'AzureLinux'
        mode: 'System'
        vnetSubnetID: systemSubnetId
        enableAutoScaling: false
        type: 'VirtualMachineScaleSets'
        nodeTaints: [
          'CriticalAddonsOnly=true:NoSchedule'
        ]
        nodeLabels: {
          'nodepool-type': 'system'
        }
      }
      {
        name: 'user'
        count: userNodeCount
        minCount: userNodeCountMin
        maxCount: userNodeCountMax
        vmSize: userNodeSize
        osType: 'Linux'
        osSKU: 'AzureLinux'
        mode: 'User'
        vnetSubnetID: userSubnetId
        enableAutoScaling: true
        type: 'VirtualMachineScaleSets'
        nodeLabels: {
          'nodepool-type': 'user'
          'workload': 'neo4j'
        }
        tags: {
          workload: 'neo4j'
        }
      }
    ]

    // Network configuration
    networkProfile: {
      networkPlugin: 'azure'
      networkPolicy: 'azure'
      loadBalancerSku: 'standard'
      outboundType: 'loadBalancer'
      serviceCidr: '172.16.0.0/16'
      dnsServiceIP: '172.16.0.10'
    }

    // Azure Monitor integration
    addonProfiles: {
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalytics.id
        }
      }
      azurePolicy: {
        enabled: true
      }
    }

    // Auto-upgrade configuration
    autoUpgradeProfile: {
      upgradeChannel: 'stable'
    }

    // Disable local accounts (use Azure AD only)
    disableLocalAccounts: false
  }
}

// Diagnostic settings for control plane logs
resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: '${clusterName}-diagnostics'
  scope: aksCluster
  properties: {
    workspaceId: logAnalytics.id
    logs: [
      {
        category: 'kube-apiserver'
        enabled: true
      }
      {
        category: 'kube-controller-manager'
        enabled: true
      }
      {
        category: 'kube-scheduler'
        enabled: true
      }
      {
        category: 'kube-audit'
        enabled: true
      }
      {
        category: 'cluster-autoscaler'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// Role assignment for managed identity to access AKS cluster
resource clusterUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aksCluster.id, identityPrincipalId, 'aks-cluster-user')
  scope: aksCluster
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', aksClusterUserRoleId)
    principalId: identityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs
output clusterId string = aksCluster.id
output clusterName string = aksCluster.name
output oidcIssuerUrl string = aksCluster.properties.oidcIssuerProfile.issuerURL
output kubeletIdentityObjectId string = aksCluster.properties.identityProfile.kubeletidentity.objectId
output nodeResourceGroup string = aksCluster.properties.nodeResourceGroup
output logAnalyticsWorkspaceId string = logAnalytics.id
output fqdn string = aksCluster.properties.fqdn
