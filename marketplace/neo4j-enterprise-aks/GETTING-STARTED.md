# Getting Started with Neo4j on Azure Kubernetes Service

This guide walks you through deploying Neo4j Enterprise Edition on Azure Kubernetes Service (AKS) for the first time.

## What You'll Deploy

A complete Neo4j deployment on AKS including:
- **AKS Cluster** with managed Kubernetes
- **Neo4j Enterprise** (standalone or cluster)
- **Persistent Storage** using Azure Premium SSD
- **External Access** via LoadBalancer
- **Monitoring** with Azure Monitor integration

**Deployment Time:** 15-20 minutes

## Prerequisites

### Required Tools

1. **Azure CLI** (`az`) version 2.50.0 or later
   ```bash
   az --version
   az login
   ```

2. **kubectl** version 1.28 or later
   ```bash
   kubectl version --client
   ```

3. **Bicep CLI** version 0.20.0 or later (bundled with Azure CLI)
   ```bash
   az bicep version
   ```

### Azure Requirements

- **Active Azure subscription** with sufficient quotas
- **Permissions**: Contributor access to subscription or resource group
- **Quotas**:
  - At least 10 vCPUs for Standard_D or Standard_E series VMs
  - Ability to create AKS clusters
  - Ability to create public IPs and load balancers

### Optional: Validation Framework

For automated deployment and validation:
- **Python 3.12+** with `uv` package manager
- Used by the `deployments/` test framework

## Deployment Methods

Choose the method that best fits your workflow:

### Method 1: Quick Deploy Script (Recommended for Testing)

**Best for:** Quick testing and development

```bash
cd marketplace/neo4j-enterprise-aks
./deploy.sh my-resource-group
```

This script:
- Creates the resource group automatically
- Uses default parameters from `parameters.json`
- Compiles Bicep and deploys
- Shows deployment progress
- Displays connection information when complete

**Default configuration:**
- Standalone Neo4j 5.x
- Standard_E4s_v5 VM (4 vCPU, 32GB RAM)
- 32GB Premium SSD storage
- Evaluation license (30 days)

### Method 2: Validation Framework (Recommended for Development)

**Best for:** Iterative development and testing

**Setup** (one-time):
```bash
cd deployments
uv run neo4j-deploy setup
```

Follow the interactive wizard to configure:
- Azure subscription and region
- Resource naming prefix
- Password strategy (Key Vault recommended)
- Cleanup behavior

**Deploy:**
```bash
# Deploy with a specific scenario
uv run neo4j-deploy deploy --scenario standard-aks-v5

# Monitor deployment (updates every 30 seconds)
# Takes 15-20 minutes

# Validate deployment
uv run neo4j-deploy test

# Or validate specific scenario
uv run validate_deploy standard-aks-v5
```

**Cleanup:**
```bash
# Clean up specific deployment
uv run neo4j-deploy cleanup --deployment <deployment-id> --force

# Clean up all test deployments
uv run neo4j-deploy cleanup --all --force
```

### Method 3: Azure CLI (Recommended for Production)

**Best for:** Production deployments with custom configuration

```bash
cd marketplace/neo4j-enterprise-aks

# Create resource group
az group create --name my-neo4j-rg --location eastus

# Deploy with custom parameters
az deployment group create \
  --resource-group my-neo4j-rg \
  --template-file main.bicep \
  --parameters nodeCount=1 \
               graphDatabaseVersion="5" \
               adminPassword="YourSecurePassword123!" \
               licenseType="Evaluation" \
               diskSize=64
```

**Monitor deployment:**
```bash
# Watch deployment status
az deployment group show \
  --resource-group my-neo4j-rg \
  --name main \
  --query "properties.provisioningState"

# View deployment outputs
az deployment group show \
  --resource-group my-neo4j-rg \
  --name main \
  --query "properties.outputs"
```

## Step-by-Step Walkthrough

This section provides a detailed walkthrough using **Method 1** (Quick Deploy Script).

### Step 1: Prepare Environment

```bash
# Clone repository (if not already done)
git clone https://github.com/neo4j-partners/azure-resource-manager-neo4j.git
cd azure-resource-manager-neo4j/marketplace/neo4j-enterprise-aks

# Verify prerequisites
az --version        # Should be 2.50.0+
kubectl version --client  # Should be 1.28+
az account show     # Verify logged in to correct subscription
```

### Step 2: Review Parameters

Open `parameters.json` to see default configuration:

```json
{
  "nodeCount": 1,              // Standalone instance
  "graphDatabaseVersion": "5", // Neo4j 5.x
  "adminPassword": "...",      // Change this!
  "licenseType": "Evaluation", // 30-day trial
  "diskSize": 32,              // 32 GB storage
  "userNodeSize": "Standard_E4s_v5"
}
```

**Optional:** Edit `parameters.json` to customize deployment.

### Step 3: Deploy

```bash
./deploy.sh my-neo4j-test
```

**Expected output:**
```
Creating resource group: my-neo4j-test
Resource group created successfully
Deploying main.bicep to my-neo4j-test...
Deployment in progress...
```

**Deployment phases:**
1. **Infrastructure** (5-8 min): VNet, AKS cluster, node pools
2. **Storage** (1-2 min): StorageClass configuration
3. **Application** (5-10 min): Helm chart deployment, Neo4j startup
4. **LoadBalancer** (2-3 min): External IP assignment

### Step 4: Monitor Deployment

**In another terminal**, watch resources being created:

```bash
# Get AKS credentials (after cluster is created)
az aks get-credentials \
  --resource-group my-neo4j-test \
  --name <cluster-name>  # From deployment output

# Watch pods being created
kubectl get pods -n neo4j -w

# Check deployment status
kubectl get all -n neo4j
```

**Expected pod progression:**
```
neo4j-0   0/1   Init:0/1        0s   # Init container
neo4j-0   0/1   PodInitializing 15s  # Starting main container
neo4j-0   0/1   Running         30s  # Container running, Neo4j starting
neo4j-0   1/1   Running         2m   # Ready! Health checks passing
```

### Step 5: Get Connection Information

When deployment completes, the script displays:

```
Deployment complete!
Neo4j Browser: http://<external-ip>:7474
Bolt URI:      neo4j://<external-ip>:7687
Username:      neo4j
Password:      <your-password>
```

**Or retrieve manually:**
```bash
# Get external IP
kubectl get service neo4j -n neo4j

# Get connection details from deployment outputs
az deployment group show \
  --resource-group my-neo4j-test \
  --name main \
  --query "properties.outputs" \
  --output yaml
```

## Accessing Neo4j

### Via Neo4j Browser (Web UI)

1. **Open browser** to `http://<external-ip>:7474`
2. **Login** with:
   - Username: `neo4j`
   - Password: `<your-admin-password>`
3. **Run test query:**
   ```cypher
   RETURN "Hello Neo4j on AKS!" AS message
   ```

**Expected result:** Should see your message returned.

### Via Neo4j Driver (Python Example)

```python
from neo4j import GraphDatabase

# Connection details
uri = "neo4j://<external-ip>:7687"
username = "neo4j"
password = "<your-password>"

# Connect
driver = GraphDatabase.driver(uri, auth=(username, password))

# Run query
with driver.session() as session:
    result = session.run("RETURN 'Connected!' AS message")
    print(result.single()["message"])

driver.close()
```

### Via kubectl (Direct Pod Access)

```bash
# Get AKS credentials
az aks get-credentials \
  --resource-group my-neo4j-test \
  --name <cluster-name>

# View Neo4j pods
kubectl get pods -n neo4j

# Check pod logs
kubectl logs neo4j-0 -n neo4j

# Follow logs in real-time
kubectl logs neo4j-0 -n neo4j -f

# Execute cypher-shell inside pod
kubectl exec -it neo4j-0 -n neo4j -- cypher-shell -u neo4j -p <password>

# Port forward for local access (localhost:7474 and localhost:7687)
kubectl port-forward neo4j-0 7474:7474 7687:7687 -n neo4j
```

## Verifying Deployment

### Quick Verification

**1. Check pod health:**
```bash
kubectl get pods -n neo4j
```
Expected: `STATUS: Running`, `READY: 1/1`

**2. Check service:**
```bash
kubectl get svc -n neo4j
```
Expected: `neo4j` service with `EXTERNAL-IP` (not `<pending>`)

**3. Test connection:**
```bash
# Via Browser: Open http://<external-ip>:7474
# Should see Neo4j login screen
```

### Comprehensive Validation

**Using validation framework:**
```bash
cd deployments
uv run validate_deploy standard-aks-v5
```

**Validation tests:**
- ✅ Connects to Neo4j via Bolt protocol
- ✅ Creates test graph (Movies dataset)
- ✅ Runs Cypher queries
- ✅ Verifies data persistence
- ✅ Checks license type
- ✅ Cleans up test data

**Manual validation:**

```cypher
// 1. Create test data
CREATE (n:Test {created: datetime(), message: 'Deployment verified!'})
RETURN n

// 2. Query test data
MATCH (n:Test) RETURN n

// 3. Check version
CALL dbms.components() YIELD name, versions, edition

// 4. Check license (for Enterprise)
CALL dbms.showCurrentUser()

// 5. Clean up
MATCH (n:Test) DELETE n
```

### Performance Check

```cypher
// Check memory configuration
CALL dbms.listConfig()
YIELD name, value
WHERE name STARTS WITH 'server.memory'
RETURN name, value

// Check active connections
CALL dbms.listConnections()

// Run performance test
UNWIND range(1, 1000) AS i
CREATE (n:PerfTest {id: i, timestamp: timestamp()})
```

## Troubleshooting

### Pod Won't Start

**Symptoms:** Pod stuck in `Pending`, `Init`, or `CrashLoopBackOff`

**Check pod details:**
```bash
kubectl describe pod neo4j-0 -n neo4j
kubectl logs neo4j-0 -n neo4j
kubectl get events -n neo4j --sort-by='.lastTimestamp'
```

**Common causes:**
- **Insufficient resources:** Node pool too small or memory limits too high
- **PVC not binding:** Check `kubectl get pvc -n neo4j`
- **Image pull errors:** Check image name and registry access
- **Init container failing:** Check init container logs

**Solutions:**
```bash
# Check node capacity
kubectl describe nodes | grep -A 5 "Allocated resources"

# Check PVC status
kubectl get pvc -n neo4j
kubectl describe pvc data-neo4j-0 -n neo4j

# Check storage class
kubectl get storageclass neo4j-premium
```

### Cannot Connect Externally

**Symptoms:** Browser cannot reach `http://<external-ip>:7474`

**Check service:**
```bash
kubectl get svc neo4j -n neo4j
```

**If EXTERNAL-IP shows `<pending>`:**
- Wait 2-3 minutes (LoadBalancer provisioning takes time)
- Check Azure subscription has available public IPs

**If EXTERNAL-IP is assigned but can't connect:**
```bash
# Check NSG rules
az network nsg list --resource-group <node-resource-group>

# Verify ports 7474 and 7687 are allowed
# Test from Azure Cloud Shell (bypasses local firewall)
curl http://<external-ip>:7474
```

**Test from inside cluster:**
```bash
kubectl run -it --rm debug --image=busybox --restart=Never -n neo4j -- \
  wget -O- http://neo4j-0.neo4j:7474
```

### Data Not Persisting

**Symptoms:** Data lost after pod restart

**Check PVC is bound:**
```bash
kubectl get pvc -n neo4j
```
Expected: `STATUS: Bound`

**Verify volume mount:**
```bash
kubectl describe pod neo4j-0 -n neo4j | grep -A 10 "Mounts:"
```
Expected: `/data` mounted from PVC

**Test persistence:**
```bash
# 1. Create test data in Neo4j Browser
CREATE (n:PersistenceTest {value: 'before restart'})

# 2. Delete pod (will be recreated by StatefulSet)
kubectl delete pod neo4j-0 -n neo4j

# 3. Wait for pod to restart (1-2 minutes)
kubectl get pods -n neo4j -w

# 4. Query test data (should still exist)
MATCH (n:PersistenceTest) RETURN n
```

### Helm Deployment Failures

**Symptoms:** Deployment script shows Helm errors

**Check Helm deployment status:**
```bash
# List Helm releases
helm list -n neo4j

# Check release status
helm status neo4j -n neo4j

# View Helm values
helm get values neo4j -n neo4j
```

**Common issues:**
- **Chart version mismatch:** Check `helm-deployment.bicep` chart version (currently 5.24.0)
- **Parameter errors:** Verify Helm values match chart expectations
- **RBAC issues:** Check service account has necessary permissions

**See detailed troubleshooting:** [TROUBLESHOOTING.md](TROUBLESHOOTING.md)

## Cleanup

### Quick Cleanup

**Using deploy.sh:**
```bash
./delete.sh my-neo4j-test
```

This deletes the entire resource group and all contained resources.

**Using validation framework:**
```bash
cd deployments
uv run neo4j-deploy cleanup --deployment <deployment-id> --force
```

### Manual Cleanup

```bash
# Delete resource group (deletes everything)
az group delete --name my-neo4j-test --yes --no-wait

# Or delete just the deployment (keeps infrastructure)
az deployment group delete \
  --resource-group my-neo4j-test \
  --name main

# Or delete specific Kubernetes resources
kubectl delete namespace neo4j
```

**Verify cleanup:**
```bash
# Check resource group is gone
az group exists --name my-neo4j-test

# Should return: false
```

## Next Steps

### For Development

1. **Explore Kubernetes resources:**
   ```bash
   kubectl get all -n neo4j
   kubectl describe statefulset neo4j -n neo4j
   kubectl get pvc -n neo4j
   ```

2. **Review logs and monitoring:**
   ```bash
   kubectl logs neo4j-0 -n neo4j -f
   # Check Azure Monitor Container Insights in Azure Portal
   ```

3. **Test data persistence:**
   - Create data
   - Delete pod
   - Verify data survives restart

4. **Experiment with Cypher queries:**
   - Load sample datasets
   - Test query performance
   - Try different graph patterns

### For Production Planning

1. **Review architecture:** See [ARCHITECTURE.md](ARCHITECTURE.md) for detailed component design

2. **Plan cluster deployment:** For high availability, deploy with `nodeCount=3` or higher

3. **Configure parameters:** See [docs/REFERENCE.md](docs/REFERENCE.md) for all configuration options

4. **Review operations guide:** See [docs/OPERATIONS.md](docs/OPERATIONS.md) for day-2 operations

5. **Set up monitoring and backup:** Configure Azure Monitor dashboards and backup procedures

### Deployment Scenarios

**Standalone (Development/Testing):**
```bash
--parameters nodeCount=1 graphDatabaseVersion="5"
```

**Cluster (Production):**
```bash
--parameters nodeCount=3 graphDatabaseVersion="5"
```

**Large Storage:**
```bash
--parameters diskSize=128
```

**Different VM Size:**
```bash
--parameters userNodeSize="Standard_E8s_v5"
```

## Additional Resources

- **Architecture Details:** [ARCHITECTURE.md](ARCHITECTURE.md)
- **Parameter Reference:** [docs/REFERENCE.md](docs/REFERENCE.md)
- **Troubleshooting Guide:** [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
- **Cluster Discovery:** [docs/CLUSTER-DISCOVERY.md](docs/CLUSTER-DISCOVERY.md)
- **Neo4j Kubernetes Docs:** https://neo4j.com/docs/operations-manual/5/kubernetes/
- **Neo4j Helm Charts:** https://github.com/neo4j/helm-charts
- **AKS Documentation:** https://docs.microsoft.com/en-us/azure/aks/

## Getting Help

If you encounter issues:

1. **Check troubleshooting guide:** [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
2. **Review pod logs:** `kubectl logs neo4j-0 -n neo4j`
3. **Check deployment logs:** Azure Portal → Deployments
4. **Review Helm status:** `helm status neo4j -n neo4j`
5. **Open GitHub issue:** https://github.com/neo4j-partners/azure-resource-manager-neo4j/issues
6. **Neo4j Community Forum:** https://community.neo4j.com
7. **Neo4j Support:** support@neo4j.com (Enterprise customers)

---

**Document Version:** 1.0
**Last Updated:** November 2025
**Bicep + Helm Architecture**
