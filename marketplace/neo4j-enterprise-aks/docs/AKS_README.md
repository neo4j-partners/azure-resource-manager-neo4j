# Neo4j Enterprise on Azure Kubernetes Service (AKS)

## Quick Overview

This template deploys Neo4j Enterprise Edition on Azure Kubernetes Service (AKS), providing a modern, container-based alternative to VM deployments. Neo4j runs as containerized workloads managed by Kubernetes, offering improved operational simplicity, automatic scaling, and cloud-native integration.

**Current Status:** Phase 2 Complete - Standalone deployment working

**Supported Deployment:**
- **Standalone Neo4j 5.x**: Single-node deployment for development and testing

**Coming Soon:**
- Multi-node clusters (3-5 nodes) for high availability
- Read replicas for analytics workloads
- Graph Data Science (GDS) and Bloom plugins
- Automated backup and disaster recovery

## Deploying with the Test Framework

### Prerequisites

1. **Azure CLI** installed and logged in
2. **Python 3.12+** with `uv` installed
3. **kubectl** installed for Kubernetes management
4. **Active Azure subscription** with appropriate permissions

### Setup

Navigate to the deployments directory and run setup:

```bash
cd deployments
uv run neo4j-deploy setup
```

Follow the interactive wizard to configure:
- Azure subscription
- Default region (recommend: westeurope or eastus)
- Resource naming prefix
- Password strategy (recommend: Azure Key Vault)

### Deploy Standalone AKS Scenario

Deploy a single-node Neo4j instance on AKS:

```bash
# Deploy the standard AKS scenario
uv run neo4j-deploy deploy --scenario standard-aks-v5

# Monitor deployment progress (takes 15-20 minutes)
# Deployment will show status updates every 30 seconds

# Once complete, validate the deployment
uv run validate_deploy standard-aks-v5
```

### Accessing Your Neo4j Instance

After successful deployment:

```bash
# Get connection information
cat .arm-testing/results/connection-standard-aks-v5-*.json

# Connect via Neo4j Browser
# URL will be http://<external-ip>:7474
# Username: neo4j
# Password: (from Key Vault or parameters)

# Connect via kubectl to the AKS cluster
az aks get-credentials \
  --resource-group <resource-group-name> \
  --name <aks-cluster-name>

# Check pod status
kubectl get pods -n neo4j

# View Neo4j logs
kubectl logs neo4j-0 -n neo4j -f
```

### Cleanup

Remove all deployed resources:

```bash
# Clean up specific deployment
uv run neo4j-deploy cleanup --deployment <deployment-id> --force

# Or clean up all deployments
uv run neo4j-deploy cleanup --all --force
```

## Architecture

### High-Level Components

The AKS deployment creates the following Azure and Kubernetes resources:

**Azure Infrastructure Layer:**
- **AKS Cluster**: Managed Kubernetes cluster with system and user node pools
- **Virtual Network**: Isolated network for the AKS cluster
- **Managed Identity**: Azure identity for workload authentication
- **Log Analytics Workspace**: Centralized logging and monitoring
- **Storage Account**: For backup storage (future phase)

**Kubernetes Resources Layer:**
- **Namespace**: Isolated environment for Neo4j resources
- **StorageClass**: Azure Disk configuration for persistent storage
- **ServiceAccount**: Kubernetes identity with workload identity annotations
- **ConfigMap**: Neo4j configuration settings
- **Secret**: Admin credentials and license keys
- **StatefulSet**: Neo4j pod(s) with stable identity and storage
- **PersistentVolumeClaim**: Storage for Neo4j data (per pod)
- **Services**:
  - Headless service for cluster discovery
  - LoadBalancer service for external access

**Data Flow:**
1. User deploys Bicep template via Azure CLI or Portal
2. Bicep creates AKS cluster and supporting infrastructure
3. Deployment scripts use `kubectl` to create Kubernetes resources
4. StatefulSet launches Neo4j pod(s)
5. Persistent volumes are provisioned and attached
6. LoadBalancer service exposes Neo4j externally
7. User connects via public IP on ports 7474 (HTTP) and 7687 (Bolt)

### Resource Sizing

**Standard Configuration (Standard_E4s_v5 nodes):**
- **CPU**: 2 cores requested, 3 cores limit per Neo4j pod
- **Memory**: 8Gi requested, 12Gi limit per Neo4j pod
- **Neo4j Heap**: 4GB
- **Page Cache**: 3GB
- **Storage**: 32GB Premium SSD per pod (expandable)

These settings are optimized for Standard_E4s_v5 nodes (4 vCPU, 32GB RAM), leaving headroom for Kubernetes system components.

### Template Structure

All Bicep templates are located in `marketplace/neo4j-enterprise-aks/`:

**Main Templates:**
- `main.bicep` - Orchestrates all modules, entry point for deployment
- `parameters.json` - Default parameter values for testing

**Infrastructure Modules** (`modules/` directory):
- `network.bicep` - Virtual network and subnet configuration
- `identity.bicep` - Managed identity and role assignments
- `aks-cluster.bicep` - AKS cluster, node pools, monitoring
- `storage.bicep` - StorageClass for persistent volumes

**Kubernetes Deployment Modules** (`modules/` directory):
- `namespace.bicep` - Creates Neo4j namespace
- `serviceaccount.bicep` - Service account with workload identity
- `configuration.bicep` - ConfigMap and Secret for Neo4j config
- `statefulset.bicep` - Neo4j StatefulSet with resources and probes
- `services.bicep` - Headless and LoadBalancer services
- `neo4j-app.bicep` - Orchestrates all Kubernetes resources

**UI and Packaging:**
- `createUiDefinition.json` - Azure Portal deployment wizard
- `makeArchive.sh` - Packages templates for marketplace

**Helpers:**
- `deploy.sh` - Local deployment script for testing
- `delete.sh` - Cleanup script

### Key Design Decisions

1. **No Init Containers**: Following Neo4j Kubernetes best practices, we don't use init containers. The pod's `fsGroup` security context handles directory permissions automatically.

2. **Deployment Scripts**: We use Bicep `deploymentScripts` resources to run `kubectl` commands rather than direct Kubernetes provider. This provides better error handling and state management.

3. **Separate Modules**: Each Kubernetes resource type has its own Bicep module for maintainability and reusability.

4. **Resource Limits**: CPU and memory limits are carefully tuned to fit within Standard_E4s_v5 node allocatable capacity (3.86 CPUs, 31GB RAM).

5. **Memory Configuration**: Neo4j heap and page cache are explicitly set via environment variables to prevent auto-detection issues in containers.

6. **StatefulSet Over Deployment**: Neo4j requires stable network identity and persistent storage, which StatefulSets provide.

7. **Premium SSD Storage**: We use Azure Premium SSD (managed-premium) for optimal Neo4j I/O performance.

## Differences from VM Deployment

| Aspect | VM Deployment | AKS Deployment |
|--------|---------------|----------------|
| **Compute** | Virtual Machine Scale Set | AKS node pool + Pods |
| **Installation** | Cloud-init scripts + apt/yum | Docker container image |
| **Management** | Systemd service | Kubernetes StatefulSet |
| **Storage** | Azure Managed Disks (direct attach) | Persistent Volumes (CSI driver) |
| **Networking** | Public IPs per VM | LoadBalancer service |
| **Discovery** | DNS + Azure API | Kubernetes DNS |
| **Scaling** | VMSS scale operations | kubectl scale / HPA |
| **Updates** | In-place VM updates | Rolling pod updates |
| **Monitoring** | VM insights | Container insights |

## Troubleshooting

### Pod Not Starting

```bash
# Check pod status and events
kubectl describe pod neo4j-0 -n neo4j

# Common issues:
# - Insufficient CPU/memory on nodes
# - PVC not bound (check storage class)
# - Image pull errors (check image name)
# - Security context violations (check pod security policies)
```

### Cannot Connect to Neo4j

```bash
# Verify service has external IP
kubectl get service -n neo4j

# Check pod is ready
kubectl get pods -n neo4j

# View Neo4j logs
kubectl logs neo4j-0 -n neo4j

# Test connection from within cluster
kubectl run -it --rm debug --image=busybox --restart=Never -n neo4j -- \
  wget -O- http://neo4j-0.neo4j:7474
```

### Data Not Persisting

```bash
# Check PVC status
kubectl get pvc -n neo4j

# Verify volume is mounted
kubectl describe pod neo4j-0 -n neo4j | grep -A 5 Mounts

# Check storage class exists
kubectl get storageclass
```

## Next Steps

### For Development

1. **Explore the deployment** - Use `kubectl` to inspect resources
2. **Test queries** - Connect via Neo4j Browser or Cypher Shell
3. **Check logs** - View Neo4j startup and query logs
4. **Test persistence** - Delete pod and verify data survives

### For Production Planning

1. **Review Phase 3 & 4 proposals** - See planned cluster and plugin support
2. **Benchmark performance** - Compare to VM deployment for your workload
3. **Plan capacity** - Size node pools based on expected load
4. **Design backup strategy** - Plan for volume snapshots and exports

## Additional Resources

- **Architecture Details**: See `/AKS.md` in the repository root for comprehensive architecture documentation
- **Neo4j Kubernetes Best Practices**: https://neo4j.com/docs/operations-manual/5/kubernetes/
- **Neo4j Helm Charts**: https://github.com/neo4j/helm-charts
- **AKS Documentation**: https://docs.microsoft.com/en-us/azure/aks/

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review Neo4j Kubernetes documentation
3. Check deployment logs in Log Analytics
4. Open an issue in the GitHub repository

---

**Last Updated**: November 2025
**Template Version**: Phase 2 (Standalone deployment)
**Neo4j Version Supported**: 5.x Enterprise
