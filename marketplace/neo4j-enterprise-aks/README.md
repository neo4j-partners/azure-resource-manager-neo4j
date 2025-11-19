# Neo4j Enterprise on Azure Kubernetes Service (AKS)

This directory contains Azure Bicep templates for deploying Neo4j Enterprise Edition on Azure Kubernetes Service (AKS).

## Overview

This deployment option provides a modern, container-based alternative to the VM-based deployment, offering:

- **Cloud-native architecture** using Kubernetes primitives
- **Automatic scaling** and self-healing capabilities
- **Simplified operations** with Kubernetes tooling
- **Consistent deployment patterns** across environments

## Architecture

The deployment consists of two main layers:

### Infrastructure Layer
- **AKS Cluster**: Managed Kubernetes cluster with system and user node pools
- **Virtual Network**: Isolated network with subnets for cluster components
- **Managed Identity**: Workload Identity for secure Azure service authentication
- **Storage**: Premium SSD storage class for persistent data volumes
- **Monitoring**: Azure Monitor integration with Container Insights

### Application Layer
- **StatefulSet**: Neo4j pods with stable network identities
- **Persistent Volumes**: Azure Disk-backed storage for data persistence
- **Services**: Headless service for discovery and LoadBalancer for external access
- **Configuration**: ConfigMaps and Secrets for Neo4j settings

## Deployment Scenarios

- **Standalone**: Single-instance Neo4j (nodeCount=1)
- **Cluster**: Multi-node Neo4j cluster (nodeCount=3-10)
- **Analytics**: Optimized for read-heavy workloads

## Prerequisites

- Azure CLI (`az`) version 2.50.0 or later
- Bicep CLI version 0.20.0 or later
- kubectl version 1.28 or later
- Active Azure subscription with sufficient quotas
- Contributor access to subscription or resource group

## Quick Start

### Deploy Standalone Instance

```bash
./deploy.sh my-resource-group
```

### Deploy with Custom Parameters

```bash
az deployment group create \
  --resource-group my-resource-group \
  --template-file main.bicep \
  --parameters nodeCount=3 \
               graphDatabaseVersion="5" \
               adminPassword="YourSecurePassword123!" \
               licenseType="Evaluation"
```

## Parameters

### Required Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `nodeCount` | int | Number of Neo4j instances (1, 3-10) |
| `graphDatabaseVersion` | string | Neo4j version ("5" or "4.4") |
| `adminPassword` | securestring | Neo4j admin password |
| `licenseType` | string | "Enterprise" or "Evaluation" |
| `diskSize` | int | Data disk size in GB (minimum 32) |

### Optional Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `location` | string | resourceGroup().location | Azure region |
| `resourceNamePrefix` | string | "neo4j" | Prefix for resource names |
| `kubernetesVersion` | string | "1.28" | Kubernetes version |
| `userNodeSize` | string | "Standard_E4s_v5" | VM size for Neo4j nodes |
| `userNodeCountMin` | int | 1 | Minimum node pool size |
| `userNodeCountMax` | int | 10 | Maximum node pool size |

## Outputs

After deployment, the following information is available:

- `neo4jBrowserUrl`: HTTP URL for Neo4j Browser
- `neo4jBoltUri`: Connection URI for Neo4j drivers
- `neo4jUsername`: Database username (always "neo4j")
- `aksClusterName`: Name of the AKS cluster
- `resourceGroupName`: Name of the resource group

## Connecting to Neo4j

### Via Neo4j Browser

1. Get the browser URL from deployment outputs
2. Navigate to the URL in your web browser
3. Login with username `neo4j` and your admin password

### Via Neo4j Driver

```python
from neo4j import GraphDatabase

uri = "neo4j://<external-ip>:7687"
driver = GraphDatabase.driver(uri, auth=("neo4j", "password"))

with driver.session() as session:
    result = session.run("RETURN 'Hello Neo4j' AS message")
    print(result.single()["message"])

driver.close()
```

### Via kubectl

```bash
# Get AKS credentials
az aks get-credentials --name <cluster-name> --resource-group <resource-group>

# View Neo4j pods
kubectl get pods -n neo4j

# View Neo4j logs
kubectl logs neo4j-0 -n neo4j

# Port forward for local access
kubectl port-forward neo4j-0 7474:7474 7687:7687 -n neo4j
```

## Troubleshooting

### Pod Won't Start

```bash
# Check pod status
kubectl describe pod neo4j-0 -n neo4j

# View pod logs
kubectl logs neo4j-0 -n neo4j

# Check events
kubectl get events -n neo4j --sort-by='.lastTimestamp'
```

### Can't Connect Externally

```bash
# Verify service has external IP
kubectl get svc neo4j-lb -n neo4j

# Check if IP is still pending (may take 2-3 minutes)
# Verify NSG rules allow traffic on ports 7474 and 7687
```

### PVC Won't Bind

```bash
# Check PVC status
kubectl get pvc -n neo4j

# Check storage class
kubectl get storageclass neo4j-premium

# View PVC events
kubectl describe pvc data-neo4j-0 -n neo4j
```

## Cleanup

To delete all resources:

```bash
./delete.sh my-resource-group
```

## Module Structure

- `main.bicep`: Main orchestration template
- `modules/network.bicep`: Virtual network and NSG
- `modules/identity.bicep`: Managed identity and Workload Identity
- `modules/aks-cluster.bicep`: AKS cluster with node pools
- `modules/storage.bicep`: Storage class configuration
- `modules/namespace.bicep`: Kubernetes namespace
- `modules/serviceaccount.bicep`: Service account with Workload Identity
- `modules/configuration.bicep`: ConfigMap and Secret
- `modules/statefulset.bicep`: Neo4j StatefulSet
- `modules/services.bicep`: Kubernetes services
- `modules/neo4j-app.bicep`: Application layer orchestration

## Cost Estimation

Approximate monthly costs for standalone deployment in East US:

- AKS cluster management: Free
- System node pool (3x Standard_D2s_v5): ~$250
- User node pool (1x Standard_E4s_v5): ~$240
- Load Balancer: ~$20
- Storage (32 GB Premium SSD): ~$5
- **Total: ~$515/month**

Costs scale linearly with additional Neo4j nodes.

## Support

For issues and questions:
- GitHub Issues: https://github.com/neo4j-partners/azure-resource-manager-neo4j/issues
- Neo4j Community Forum: https://community.neo4j.com
- Neo4j Support: support@neo4j.com (Enterprise customers)

## License

Neo4j Enterprise Edition requires a valid license. This deployment supports both Enterprise licenses and 30-day Evaluation licenses.
