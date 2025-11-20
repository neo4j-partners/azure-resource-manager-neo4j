# Neo4j on AKS - Configuration Reference

Complete reference for all Bice

p parameters and Helm chart configurations.

## Overview

This deployment uses:
- **Bicep templates** for Azure infrastructure (AKS, networking, storage)
- **Official Neo4j Helm chart** (`neo4j/neo4j` v5.24.0) for application deployment

**Parameter Flow:**
```
Bicep Parameters → helm-deployment.bicep → Helm Chart Values → Neo4j Configuration
```

---

## Bicep Parameters

### Required Parameters

#### `adminPassword`
- **Type:** securestring
- **Description:** Neo4j admin password (username is always "neo4j")
- **Constraints:** Minimum 8 characters
- **Security:** Marked as @secure(), never logged
- **Example:** `"MySecureP@ssw0rd!"`

#### `nodeCount`
- **Type:** int
- **Description:** Number of Neo4j instances to deploy
- **Allowed Values:** 1, 3-10
- **Default:** 1 (standalone)
- **Usage:**
  - `1` = Standalone instance
  - `3-10` = High-availability cluster
- **Note:** 2 nodes not supported (no quorum for clustering)

#### `graphDatabaseVersion`
- **Type:** string
- **Description:** Neo4j version to deploy
- **Allowed Values:** "5", "4.4"
- **Default:** "5"
- **Recommendation:** Use "5" (4.4 is legacy support only)

#### `licenseType`
- **Type:** string
- **Description:** Neo4j license agreement type
- **Allowed Values:**
  - `"Enterprise"` - Production use with valid license
  - `"Evaluation"` - 30-day trial (no license key needed)
- **Default:** "Evaluation"

#### `diskSize`
- **Type:** int
- **Description:** Data disk size per Neo4j pod in GB
- **Constraints:** Minimum 32, Maximum 4096
- **Default:** 32
- **Recommendation:** Plan for 2-3x expected data size
- **Example Values:**
  - Development: 32-64 GB
  - Production: 128-512 GB
  - Large datasets: 1024+ GB

---

### Optional Parameters

#### Infrastructure

##### `location`
- **Type:** string
- **Description:** Azure region for all resources
- **Default:** `resourceGroup().location` (inherits from resource group)
- **Example:** "eastus", "westeurope"

##### `resourceNamePrefix`
- **Type:** string
- **Description:** Prefix for all resource names
- **Constraints:** 3-10 characters
- **Default:** "neo4j"
- **Usage:** Creates unique names like `neo4j-aks-abc123`

##### `kubernetesVersion`
- **Type:** string
- **Description:** AKS cluster Kubernetes version
- **Default:** "1.30"
- **Recommendation:** Use default or latest stable AKS version
- **Check Available:** `az aks get-versions --location eastus`

##### `systemNodeSize`
- **Type:** string
- **Description:** VM size for AKS system node pool
- **Default:** "Standard_D2s_v5"
- **Note:** Used for Kubernetes system components only

##### `userNodeSize`
- **Type:** string
- **Description:** VM size for AKS user node pool (runs Neo4j pods)
- **Default:** "Standard_E4s_v5" (4 vCPU, 32GB RAM)
- **Recommendations:**
  - Small: "Standard_E2s_v5" (2 vCPU, 16GB) - dev/test only
  - Medium: "Standard_E4s_v5" (4 vCPU, 32GB) - default
  - Large: "Standard_E8s_v5" (8 vCPU, 64GB) - production
  - X-Large: "Standard_E16s_v5" (16 vCPU, 128GB) - high-performance

##### `userNodeCountMin`
- **Type:** int
- **Description:** Minimum nodes in user node pool
- **Constraints:** 1-10
- **Default:** 1
- **Recommendation:** Set to `nodeCount` for predictable performance

##### `userNodeCountMax`
- **Type:** int
- **Description:** Maximum nodes for autoscaling
- **Constraints:** 1-10
- **Default:** 10
- **Note:** Autoscaling based on CPU/memory pressure

#### Neo4j Configuration

##### `installGraphDataScience`
- **Type:** string ("Yes" or "No")
- **Description:** Install GDS plugin
- **Default:** "No"
- **Note:** Requires GDS license key for Enterprise features

##### `graphDataScienceLicenseKey`
- **Type:** securestring
- **Description:** GDS Enterprise license key
- **Default:** "" (empty, not required for Community GDS)
- **Security:** @secure() parameter

##### `installBloom`
- **Type:** string ("Yes" or "No")
- **Description:** Install Bloom visualization plugin
- **Default:** "No"
- **Note:** Requires Bloom license key

##### `bloomLicenseKey`
- **Type:** securestring
- **Description:** Bloom license key
- **Default:** "" (empty)
- **Security:** @secure() parameter

---

## Bicep to Helm Mapping

This section shows how Bicep parameters translate to Helm chart values.

### Storage Configuration

**Bicep:**
```bicep
param diskSize int = 32
```

**Helm Values:**
```yaml
volumes:
  data:
    mode: "dynamic"
    dynamic:
      storageClassName: "neo4j-premium"
      requests:
        storage: "32Gi"
```

**Helm Command:**
```bash
--set volumes.data.mode=dynamic
--set volumes.data.dynamic.storageClassName=neo4j-premium
--set volumes.data.dynamic.requests.storage=32Gi
```

**Critical:** Use `requests.storage` NOT just `storage`!

### Neo4j Core Configuration

**Bicep:**
```bicep
param nodeCount int = 1
param licenseType string = 'Evaluation'
param adminPassword securestring
```

**Helm Values (Standalone):**
```yaml
neo4j:
  name: "neo4j-standalone"
  edition: "enterprise"
  acceptLicenseAgreement: "eval"  # or "yes" for Enterprise
  password: "<secure-password>"
```

**Helm Values (Cluster):**
```yaml
neo4j:
  name: "neo4j-cluster"
  edition: "enterprise"
  acceptLicenseAgreement: "yes"
  password: "<secure-password>"
  minimumClusterSize: 3  # Set when nodeCount >= 3
```

**Helm Command:**
```bash
--set neo4j.name=neo4j-cluster
--set neo4j.edition=enterprise
--set neo4j.acceptLicenseAgreement=yes
--set neo4j.password=$NEO4J_PASSWORD
--set neo4j.minimumClusterSize=3
```

### Resource Configuration

**Bicep:**
```bicep
param userNodeSize string = 'Standard_E4s_v5'
// Internally translated to CPU/memory requests
```

**Helm Values:**
```yaml
neo4j:
  resources:
    cpu: "2000m"     # 2 cores
    memory: "8Gi"    # 8 GB
```

**Helm Command:**
```bash
--set neo4j.resources.cpu=2000m
--set neo4j.resources.memory=8Gi
```

**Critical:** Resources are under `neo4j.resources` NOT just `resources`!

### Memory Configuration (JVM)

**Bicep:** (Auto-calculated from memory request)

**Helm Values:**
```yaml
config:
  server.memory.heap.initial_size: "4G"
  server.memory.heap.max_size: "4G"
  server.memory.pagecache.size: "3G"
```

**Helm Command:**
```bash
--set config.server\.memory\.heap\.initial_size=4G
--set config.server\.memory\.heap\.max_size=4G
--set config.server\.memory\.pagecache\.size=3G
```

**Note:** Dots must be escaped in Helm `--set` commands!

### Service Configuration

**Bicep:** (Always LoadBalancer for Azure)

**Helm Values:**
```yaml
services:
  neo4j:
    enabled: true
    spec:
      type: LoadBalancer
```

**Helm Command:**
```bash
--set services.neo4j.enabled=true
--set services.neo4j.spec.type=LoadBalancer
```

---

## Resource Sizing Guidelines

### Memory Allocation

Neo4j memory should be split between:
- **JVM Heap:** ~50% of pod memory
- **Page Cache:** ~37% of pod memory
- **OS/Overhead:** ~13% of pod memory

**Examples:**

| Pod Memory | Heap | Page Cache | OS/Overhead |
|------------|------|------------|-------------|
| 8 GB | 4 GB | 3 GB | 1 GB |
| 16 GB | 8 GB | 6 GB | 2 GB |
| 32 GB | 16 GB | 12 GB | 4 GB |
| 64 GB | 32 GB | 24 GB | 8 GB |

### VM Size Recommendations

#### Development/Testing
- **Standard_E2s_v5** (2 vCPU, 16GB RAM)
- Cost: ~$120/month per node
- Suitable for: Small datasets, development

#### Production (Small to Medium)
- **Standard_E4s_v5** (4 vCPU, 32GB RAM) ← Default
- Cost: ~$240/month per node
- Suitable for: Most production workloads

#### Production (Large)
- **Standard_E8s_v5** (8 vCPU, 64GB RAM)
- Cost: ~$480/month per node
- Suitable for: Large datasets, high throughput

#### Production (X-Large)
- **Standard_E16s_v5** (16 vCPU, 128GB RAM)
- Cost: ~$960/month per node
- Suitable for: Very large datasets, analytics

### Storage Sizing

**Formula:** `diskSize = (expected_data_size * 2.5) + overhead`

**Recommendations:**

| Data Size | Disk Size | Rationale |
|-----------|-----------|-----------|
| < 10 GB | 32 GB | Minimum, includes logs and temp files |
| 10-50 GB | 128 GB | 2.5x data + overhead |
| 50-200 GB | 512 GB | Growth room |
| 200+ GB | 1-2 TB | Production datasets |

**Note:** Azure Premium SSD performance scales with size:
- 32 GB: 120 IOPS, 25 MB/s
- 128 GB: 500 IOPS, 100 MB/s
- 512 GB: 2,300 IOPS, 150 MB/s
- 1 TB: 5,000 IOPS, 200 MB/s

---

## Configuration Examples

### Minimal Development

```bash
az deployment group create \
  --resource-group dev-neo4j \
  --template-file main.bicep \
  --parameters \
    nodeCount=1 \
    graphDatabaseVersion="5" \
    adminPassword="DevPassword123!" \
    licenseType="Evaluation" \
    diskSize=32 \
    userNodeSize="Standard_E2s_v5"
```

**Result:** Single Neo4j instance, 32GB storage, small VM
**Cost:** ~$120/month (user node) + $250 (system nodes) + ~$25 (other) = **~$395/month**

### Production Standalone

```bash
az deployment group create \
  --resource-group prod-neo4j \
  --template-file main.bicep \
  --parameters \
    nodeCount=1 \
    graphDatabaseVersion="5" \
    adminPassword="ProductionPassword123!" \
    licenseType="Enterprise" \
    diskSize=256 \
    userNodeSize="Standard_E8s_v5"
```

**Result:** Single Neo4j instance, 256GB storage, large VM
**Cost:** ~$480/month (user node) + $250 (system nodes) + ~$35 (other) = **~$765/month**

### High-Availability Cluster

```bash
az deployment group create \
  --resource-group prod-neo4j-cluster \
  --template-file main.bicep \
  --parameters \
    nodeCount=3 \
    graphDatabaseVersion="5" \
    adminPassword="ClusterPassword123!" \
    licenseType="Enterprise" \
    diskSize=512 \
    userNodeSize="Standard_E8s_v5" \
    userNodeCountMin=3 \
    userNodeCountMax=5
```

**Result:** 3-node Neo4j cluster, 512GB per node, large VMs, autoscaling
**Cost:** ~$1,440/month (3 user nodes) + $250 (system nodes) + ~$65 (other) = **~$1,755/month**

### With Plugins

```bash
az deployment group create \
  --resource-group prod-neo4j-gds \
  --template-file main.bicep \
  --parameters \
    nodeCount=1 \
    graphDatabaseVersion="5" \
    adminPassword="GdsPassword123!" \
    licenseType="Enterprise" \
    diskSize=128 \
    userNodeSize="Standard_E8s_v5" \
    installGraphDataScience="Yes" \
    graphDataScienceLicenseKey="<your-gds-license>"
```

**Result:** Single Neo4j with GDS plugin, 128GB storage, large VM
**Note:** GDS increases memory requirements (use larger VM)

---

## Default Values Summary

Quick reference for all parameters with defaults:

```yaml
# Required (no defaults)
adminPassword: <must-provide>

# Infrastructure
location: <resource-group-location>
resourceNamePrefix: "neo4j"
kubernetesVersion: "1.30"
systemNodeSize: "Standard_D2s_v5"
userNodeSize: "Standard_E4s_v5"
userNodeCountMin: 1
userNodeCountMax: 10

# Neo4j Core
nodeCount: 1
graphDatabaseVersion: "5"
licenseType: "Evaluation"
diskSize: 32

# Plugins
installGraphDataScience: "No"
graphDataScienceLicenseKey: ""
installBloom: "No"
bloomLicenseKey: ""
```

---

## Common Configuration Patterns

### Pattern 1: Quick Development Deployment

**Use Case:** Testing, development, prototyping

```bash
./deploy.sh my-dev-rg
```

Uses all defaults from `parameters.json`:
- Standalone (nodeCount=1)
- Evaluation license
- Small storage (32GB)
- Default VM size

### Pattern 2: Production-Ready Standalone

**Use Case:** Production application with moderate load

```bash
az deployment group create ... --parameters \
  nodeCount=1 \
  licenseType="Enterprise" \
  diskSize=256 \
  userNodeSize="Standard_E8s_v5" \
  userNodeCountMin=1 \
  userNodeCountMax=3
```

Features:
- Enterprise license
- Larger storage and VM
- Autoscaling enabled (1-3 nodes)

### Pattern 3: High-Availability Cluster

**Use Case:** Mission-critical applications

```bash
az deployment group create ... --parameters \
  nodeCount=5 \
  licenseType="Enterprise" \
  diskSize=512 \
  userNodeSize="Standard_E8s_v5" \
  userNodeCountMin=5 \
  userNodeCountMax=5
```

Features:
- 5-node cluster for redundancy
- Large storage per node
- Fixed node count (no autoscaling during operations)

### Pattern 4: Analytics Workload with GDS

**Use Case:** Graph analytics, machine learning

```bash
az deployment group create ... --parameters \
  nodeCount=1 \
  licenseType="Enterprise" \
  diskSize=256 \
  userNodeSize="Standard_E16s_v5" \
  installGraphDataScience="Yes" \
  graphDataScienceLicenseKey="<license>"
```

Features:
- Very large VM (16 vCPU, 128GB RAM)
- GDS plugin for graph algorithms
- Large memory for in-memory graph projections

---

## Validation

After deployment, verify configuration:

```bash
# Get AKS credentials
az aks get-credentials --name <cluster-name> --resource-group <rg-name>

# Check pod resources
kubectl describe pod neo4j-0 -n neo4j | grep -A 10 "Requests:"

# Check storage
kubectl get pvc -n neo4j

# Check Neo4j config (inside pod)
kubectl exec neo4j-0 -n neo4j -- cat /var/lib/neo4j/conf/neo4j.conf

# Check memory settings
kubectl exec neo4j-0 -n neo4j -- \
  cypher-shell -u neo4j -p <password> \
  "CALL dbms.listConfig() YIELD name, value WHERE name STARTS WITH 'server.memory' RETURN name, value"
```

---

## Troubleshooting Common Configuration Issues

### Issue: Pod Won't Start (Insufficient Resources)

**Symptom:** Pod stuck in `Pending` state

**Check:**
```bash
kubectl describe pod neo4j-0 -n neo4j
```

**Solution:** VM size too small for requested resources. Increase `userNodeSize` or reduce `nodeCount`.

### Issue: Disk Performance Problems

**Symptom:** Slow queries, high I/O wait

**Check:**
```bash
# Check PVC size
kubectl get pvc -n neo4j

# Check actual disk performance in Azure Portal
```

**Solution:** Increase `diskSize` (Premium SSD performance scales with size).

### Issue: Memory Errors in Neo4j Logs

**Symptom:** `java.lang.OutOfMemoryError`

**Check:**
```bash
kubectl logs neo4j-0 -n neo4j | grep -i memory
```

**Solution:**
1. Increase `userNodeSize` for more memory
2. Adjust heap size ratio (currently 50% of pod memory)
3. Enable GDS only if needed (uses significant memory)

---

## References

- **Neo4j Helm Chart:** https://github.com/neo4j/helm-charts
- **Neo4j K8s Docs:** https://neo4j.com/docs/operations-manual/current/kubernetes/
- **Azure VM Sizes:** https://docs.microsoft.com/en-us/azure/virtual-machines/sizes
- **Azure Premium SSD:** https://docs.microsoft.com/en-us/azure/virtual-machines/disks-types

---

**Document Version:** 1.0
**Last Updated:** November 2025
**Chart Version:** neo4j/neo4j 5.24.0
