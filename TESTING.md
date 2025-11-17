# Testing Neo4j Enterprise Standalone Deployment

**Purpose:** Simple commands to test the Neo4j Enterprise standalone deployment with cloud-init

---

## Prerequisites

- Azure CLI installed and logged in
- Azure subscription with permissions to create resources
- Bicep CLI (bundled with Azure CLI 2.20.0+)

---

## Easiest Way: Use the Test Script

```bash
cd marketplace/neo4j-enterprise
./test.sh
```

**That's it!** The script will:
- Create a resource group
- Deploy Neo4j standalone
- Wait for it to start
- Validate with Neo4j Python driver
- Give you the URL and password
- Tell you how to clean up

**Note:** Requires `uv` for Python validation. Install with:
```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

---

## Manual Testing (If You Want More Control)

### 1. Set Variables

```bash
# Set your resource group name
RESOURCE_GROUP="neo4j-test-$(date +%Y%m%d-%H%M%S)"
LOCATION="eastus"
PASSWORD="YourSecurePassword123!"
```

### 2. Create Resource Group

```bash
az group create \
  --name $RESOURCE_GROUP \
  --location $LOCATION
```

### 3. Deploy Neo4j Standalone

```bash
cd marketplace/neo4j-enterprise

az deployment group create \
  --resource-group $RESOURCE_GROUP \
  --template-file mainTemplate.bicep \
  --parameters adminPassword="$PASSWORD" \
               vmSize="Standard_E4s_v5" \
               nodeCount=1 \
               diskSize=32 \
               graphDatabaseVersion="5" \
               licenseType="Evaluation" \
               installGraphDataScience="No" \
               graphDataScienceLicenseKey="None" \
               installBloom="No" \
               bloomLicenseKey="None"
```

### 4. Get Neo4j URL

```bash
# Get the deployment outputs
NEO4J_URL=$(az deployment group show \
  --resource-group $RESOURCE_GROUP \
  --name $(az deployment group list --resource-group $RESOURCE_GROUP --query "[0].name" -o tsv) \
  --query properties.outputs.neo4jBrowserURL.value \
  -o tsv)

echo "Neo4j Browser URL: $NEO4J_URL"
```

### 5. Test Connection

**Wait 5-10 minutes for Neo4j to start**, then:

```bash
# Test HTTP endpoint
curl -I $NEO4J_URL

# Should return: HTTP/1.1 200 OK
```

Open in browser:
```bash
open $NEO4J_URL  # macOS
# Or just copy the URL and paste in browser
```

**Login credentials:**
- Username: `neo4j`
- Password: `YourSecurePassword123!` (or whatever you set)

### 6. Verify Neo4j Works

In the Neo4j Browser, run:

```cypher
// Create a test node
CREATE (n:Test {name: 'Hello from cloud-init!'})
RETURN n
```

If you see the node created, **the deployment works!**

### 7. Clean Up

```bash
# Delete the resource group when done testing
az group delete --name $RESOURCE_GROUP --yes --no-wait
```

---

## Standalone Validation Script

You can also run just the validation script against any Neo4j instance:

```bash
# Using uv (automatically handles dependencies)
uv run validate.py bolt://your-neo4j-host:7687 neo4j yourpassword

# Example with local Neo4j
uv run validate.py bolt://localhost:7687 neo4j password123

# Example with Azure deployment
uv run validate.py bolt://vm0.node-xyz.eastus.cloudapp.azure.com:7687 neo4j password123
```

**What it does:**
- Connects to Neo4j using the Python driver
- Creates a test node
- Counts existing nodes
- Cleans up test data
- Reports success or failure

**Why uv?**
- No virtual environment setup needed
- Dependencies declared inline in the script
- Automatically installs neo4j driver
- Follows modern Python best practices

---

## Troubleshooting

### Deployment fails

```bash
# Check deployment status
az deployment group show \
  --resource-group $RESOURCE_GROUP \
  --name $(az deployment group list --resource-group $RESOURCE_GROUP --query "[0].name" -o tsv)
```

### Can't connect to Neo4j

```bash
# SSH into the VM to check logs
VM_NAME=$(az vm list --resource-group $RESOURCE_GROUP --query "[0].name" -o tsv)

# Get public IP
VM_IP=$(az vm list-ip-addresses \
  --resource-group $RESOURCE_GROUP \
  --name $VM_NAME \
  --query "[0].virtualMachine.network.publicIpAddresses[0].ipAddress" \
  -o tsv)

# SSH in
ssh neo4j@$VM_IP

# Check cloud-init status
sudo cloud-init status

# Check cloud-init logs
sudo cat /var/log/cloud-init-output.log

# Check Neo4j status
sudo systemctl status neo4j

# Check Neo4j logs
sudo journalctl -u neo4j -n 100
```

---

## What's Different with Cloud-Init?

**Before (bash scripts):**
- Downloaded script from GitHub during deployment
- Script URL hardcoded in template
- Required external dependency

**Now (cloud-init):**
- YAML embedded directly in Bicep template
- No external downloads
- Self-contained deployment

**To verify cloud-init is being used:**

```bash
# SSH into VM
ssh neo4j@$VM_IP

# Check cloud-init config
sudo cloud-init query userdata

# Should show the cloud-init YAML, not a script download
```

---

## Expected Timeline

- **Deployment:** 5-10 minutes
- **Neo4j startup:** 2-5 minutes
- **Total:** ~10-15 minutes from deployment start to usable Neo4j

---

## Next Steps

Once standalone deployment works:
- Phase 2: Add Azure Key Vault for password management
- Phase 3: Test with different VM sizes and disk configurations
- Phase 4: Extend to cluster deployments

---

**Last Updated:** 2025-11-17
