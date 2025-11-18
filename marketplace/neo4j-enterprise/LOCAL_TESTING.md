# Local Testing Guide for Neo4j Enterprise ARM Template

This guide focuses on testing the Neo4j Enterprise ARM template (`marketplace/neo4j-enterprise/`) locally before submitting changes.

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Understanding the Template](#understanding-the-template)
3. [Current Manual Testing Process](#current-manual-testing-process)
4. [ARM Template Best Practices (2024-2025)](#arm-template-best-practices-2024-2025)
5. [Python Testing Script Proposal](#python-testing-script-proposal)

---

## Prerequisites

### Required Tools
- **Azure CLI** (version 2.50.0 or later)
  ```bash
  az --version
  az login
  ```
- **jq** - JSON processor for parsing outputs and parameters
- **git** - For branch management and artifact location URLs

### Azure Subscription Requirements
- Active Azure subscription with sufficient quota for:
  - VM Scale Sets (up to 10 instances)
  - Standard Load Balancer (for clusters)
  - Public IP addresses
  - Virtual Networks
  - Managed Identities with role assignments
- Permissions to create:
  - Resource groups
  - Custom role definitions
  - Role assignments at resource group scope

### Recommended Permissions
- `Contributor` role on subscription or resource group
- `User Access Administrator` for creating role assignments
- Or a custom role combining both capabilities

---

## Understanding the Template

### Azure Resources Created

The `mainTemplate.json` deploys the following resources:

1. **Network Security Group** - Opens ports 22 (SSH), 7473 (HTTPS), 7474 (HTTP), 7687 (Bolt)
2. **Virtual Network** - 10.0.0.0/8 address space with 10.0.0.0/16 subnet
3. **Public IP Address** - Created conditionally when `nodeCount >= 3` or read replicas exist
4. **Load Balancer** - Standard SKU with health probes, created for clusters only
5. **User-Assigned Managed Identity** - For VMs to query scale set information
6. **Custom Role Definition** - Minimal permissions for scale set discovery
7. **Role Assignment** - Assigns custom role to managed identity
8. **VM Scale Sets** - Two types:
   - **Primary VMSS**: Core Neo4j cluster nodes (1-10 instances)
   - **Read Replica VMSS**: Optional read replicas (0-10 instances, Neo4j 4.4 only)

### Key Template Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `adminPassword` | securestring | (required) | Neo4j admin password |
| `vmSize` | string | (required) | Azure VM size for cluster nodes |
| `nodeCount` | int | (required) | 1 for standalone, 3-10 for cluster |
| `graphDatabaseVersion` | string | (required) | "5" or "4.4" |
| `diskSize` | int | (required) | Data disk size in GB |
| `licenseType` | string | "Enterprise" | "Enterprise" or "Evaluation" |
| `installGraphDataScience` | string | "No" | "Yes" or "No" |
| `installBloom` | string | "No" | "Yes" or "No" |
| `readReplicaCount` | int | 0 | Number of read replicas (4.4 only) |
| `_artifactsLocation` | string | (auto) | Base URL for installation scripts |

### Template Outputs

- **Neo4jBrowserURL** - URL for standalone deployments (nodeCount=1)
- **Neo4jClusterBrowserURL** - URL for cluster deployments (nodeCount>=3)
- **Neo4jBloomURL** / **Neo4jClusterBloomURL** - Bloom URLs if enabled
- **Username** - Always returns "neo4j"

### Installation Scripts Referenced

The template downloads and executes scripts from the `_artifactsLocation`:
- `scripts/neo4j-enterprise/node.sh` - For Neo4j 5.x deployments
- `scripts/neo4j-enterprise/node4.sh` - For Neo4j 4.4 cluster nodes
- `scripts/neo4j-enterprise/readreplica4.sh` - For Neo4j 4.4 read replicas

---

## Current Manual Testing Process

### Existing Test Files

**Files that exist:**
- `deploy.sh` - Simple deployment script
- `delete.sh` - Resource group deletion script
- `parameters.json` - Test parameter values
- `mainTemplate.json` - The ARM template

### Step-by-Step Manual Process

#### 1. Update Artifact Location (For Branch Testing)

Edit `parameters.json` and update `_artifactsLocation`:
```json
"_artifactsLocation": {
  "value": "https://raw.githubusercontent.com/neo4j-partners/azure-resource-manager-neo4j/YOUR-BRANCH-NAME/"
}
```

**Critical**: This must point to your branch so the VM extensions download the correct installation scripts.

#### 2. Review and Customize Parameters

Edit `parameters.json` to configure your test:
- `nodeCount`: 1 for standalone, 3 for minimal cluster
- `vmSize`: Use smaller VMs for testing (e.g., "Standard_E4s_v5") to reduce costs
- `diskSize`: Minimum 32 GB
- `adminPassword`: Ensure it meets Azure complexity requirements
- `graphDatabaseVersion`: "5" or "4.4"
- `licenseType`: Use "Evaluation" for testing

#### 3. Deploy Using Existing Script

```bash
cd marketplace/neo4j-enterprise
./deploy.sh test-rg-$(date +%Y%m%d-%H%M%S)
```

The script hardcodes:
- Location: `westeurope`
- Deployment name: `MyDeployment12`

#### 4. Monitor Deployment

```bash
# Watch deployment progress
az deployment group show \
  --resource-group <your-rg-name> \
  --name MyDeployment12 \
  --query properties.provisioningState

# Stream deployment logs
az deployment group show \
  --resource-group <your-rg-name> \
  --name MyDeployment12 \
  --query properties.error
```

#### 5. Retrieve Deployment Outputs

```bash
# Get all outputs
az deployment group show \
  --resource-group <your-rg-name> \
  --name MyDeployment12 \
  --query properties.outputs

# Extract specific URL
az deployment group show \
  --resource-group <your-rg-name> \
  --name MyDeployment12 \
  --query properties.outputs.neo4jBrowserURL.value -o tsv
```

#### 6. Test the Deployment

Manual verification:
- Open Neo4j Browser URL in web browser
- Login with username `neo4j` and the password from `parameters.json`
- Run basic Cypher queries: `CREATE (n:Test {name: 'test'}) RETURN n`
- Check cluster status: `CALL dbms.cluster.overview()`

Automated testing (following GitHub Actions pattern):
```bash
URI=$(az deployment group show \
  --resource-group <rg-name> \
  --name MyDeployment12 \
  --query properties.outputs.neo4jClusterBrowserURL.value -o tsv | \
  sed 's/http/neo4j/g;s/7474\//7687/g')

PASSWORD=$(cat parameters.json | jq .adminPassword.value | sed 's/"//g')

curl -LJO https://github.com/neo4j/neo4jtester/raw/main/build/neo4jtester_linux
chmod +x ./neo4jtester_linux
./neo4jtester_linux "${URI}" "neo4j" "${PASSWORD}" "Enterprise"
```

#### 7. Clean Up Resources

```bash
./delete.sh <your-rg-name>

# Or manually with confirmation
az group delete --name <your-rg-name> --yes --no-wait
```

### Limitations of Current Process

1. **Hardcoded values** - Location and deployment name are fixed in scripts
2. **No validation** - Template isn't validated before deployment
3. **No cost estimation** - No preview of resource costs
4. **No what-if analysis** - Can't preview changes before deployment
5. **Manual output extraction** - Must manually run az commands to get URLs
6. **No parallel testing** - Can't easily test multiple configurations
7. **No deployment tracking** - Difficult to manage multiple test deployments
8. **No automatic cleanup** - Must remember to delete resources
9. **Branch detection** - Must manually update `_artifactsLocation` for feature branches

---

## ARM Template Best Practices (2024-2025)

### Pre-Deployment Validation

#### 1. Template Syntax Validation
```bash
az deployment group validate \
  --resource-group <rg-name> \
  --template-file mainTemplate.json \
  --parameters @parameters.json
```

**Best Practice**: Always validate before deploying. This catches syntax errors and parameter type mismatches.

#### 2. What-If Analysis (Preview Changes)
```bash
az deployment group what-if \
  --resource-group <rg-name> \
  --template-file mainTemplate.json \
  --parameters @parameters.json
```

**Best Practice**: Use what-if to understand exactly what resources will be created, modified, or deleted. This is especially important for updates to existing deployments.

#### 3. Cost Estimation
```bash
# Export what-if results and analyze resource types
az deployment group what-if \
  --resource-group <rg-name> \
  --template-file mainTemplate.json \
  --parameters @parameters.json \
  --result-format FullResourcePayloads
```

**Best Practice**: Use Azure Pricing Calculator with what-if output to estimate costs before deploying expensive resources.

### Deployment Best Practices

#### 1. Use Deployment Stacks (New in 2024)

Deployment Stacks provide better lifecycle management and prevent resource drift:
```bash
# This is newer than traditional deployments
az stack group create \
  --name neo4j-test-stack \
  --resource-group <rg-name> \
  --template-file mainTemplate.json \
  --parameters @parameters.json \
  --deny-settings-mode none
```

**Advantage**: Stacks track all resources and can perform clean deletions, including resources created by scripts.

#### 2. Use Unique Deployment Names

Instead of hardcoding "MyDeployment12", use timestamps:
```bash
DEPLOYMENT_NAME="neo4j-deploy-$(date +%Y%m%d-%H%M%S)"
```

**Best Practice**: Unique names enable deployment history tracking and prevent conflicts.

#### 3. Tag Deployments for Tracking

Add tags to resource groups for cost tracking and cleanup:
```bash
az group create \
  --name <rg-name> \
  --location westeurope \
  --tags purpose=testing owner=<email> auto-delete=true expires=$(date -d '+1 day' +%Y-%m-%d)
```

**Best Practice**: Tags help identify test resources and automate cleanup policies.

#### 4. Use Parameter Files for Different Scenarios

Create multiple parameter files instead of editing one:
- `parameters.standalone.json` - Single node testing
- `parameters.cluster.json` - 3-node cluster testing
- `parameters.full.json` - Cluster with GDS and Bloom
- `parameters.v44.json` - Neo4j 4.4 testing

**Best Practice**: Version control different test scenarios and switch between them easily.

#### 5. Monitor Deployment Progress

Use `--no-wait` for async deployments and poll status:
```bash
az deployment group create \
  --resource-group <rg-name> \
  --name <deployment-name> \
  --template-file mainTemplate.json \
  --parameters @parameters.json \
  --no-wait

# Then monitor
az deployment group wait \
  --resource-group <rg-name> \
  --name <deployment-name> \
  --created --timeout 1800
```

**Best Practice**: Allows running multiple deployments in parallel and implementing timeouts.

### Testing Best Practices

#### 1. Test Multiple Configurations in Parallel

Deploy different configurations to separate resource groups simultaneously:
- Standalone vs Cluster
- Neo4j 5 vs 4.4
- Enterprise vs Evaluation license
- With and without plugins

**Best Practice**: Parallel testing reduces total test time from hours to minutes.

#### 2. Capture and Store Outputs

Save deployment outputs to files for later reference:
```bash
az deployment group show \
  --resource-group <rg-name> \
  --name <deployment-name> \
  --query properties.outputs > outputs-$(date +%Y%m%d-%H%M%S).json
```

**Best Practice**: Enables automated testing and debugging without manual URL extraction.

#### 3. Automated Cleanup with Lifecycle Policies

Set resource group expiration and implement automated cleanup:
```bash
# Query resource groups with expired tags
az group list \
  --query "[?tags.expires < '$(date +%Y-%m-%d)'].name" -o tsv | \
  xargs -I {} az group delete --name {} --yes --no-wait
```

**Best Practice**: Prevents forgetting to delete test resources and accumulating costs.

#### 4. Integration Testing with Real Workloads

Beyond neo4jtester, run realistic workloads:
- Load sample datasets
- Execute typical queries
- Test cluster failover
- Verify plugin functionality
- Check monitoring and metrics

**Best Practice**: Template validation only checks resource creation, not actual Neo4j functionality.

### Security Best Practices

#### 1. Never Commit Passwords

Use parameter files without passwords and provide via CLI:
```bash
az deployment group create \
  --parameters @parameters.json adminPassword="$SECURE_PASSWORD"
```

**Best Practice**: Keep `parameters.json` without password, use environment variables or Azure Key Vault.

#### 2. Review Network Security Rules

The template opens Neo4j ports to the Internet (0.0.0.0/0). For production:
- Restrict NSG rules to specific IP ranges
- Use Azure Private Link
- Implement VPN or ExpressRoute

**Best Practice**: Test templates should mirror production security where possible.

#### 3. Use Managed Identities (Already Implemented)

The template correctly uses managed identities instead of service principals with credentials.

**Best Practice**: This template already follows this best practice.

### Modern ARM Development Trends

#### 1. Consider Bicep Migration (Future)

While this template is JSON, new templates should use Bicep:
- More readable syntax
- Better tooling support
- Automatic dependency management
- Type safety

**Note**: For existing marketplace listings, JSON is often required.

#### 2. Modular Template Design

Break large templates into linked templates or modules:
- Network module
- Compute module
- Security module

**Current State**: This template is monolithic. Consider refactoring for maintainability.

#### 3. Use Template Specs

Store and version templates in Azure:
```bash
az ts create \
  --name neo4j-enterprise \
  --version "1.0" \
  --template-file mainTemplate.json \
  --location westeurope
```

**Best Practice**: Template specs provide versioning and centralized management.

---

## Python Testing Script Proposal

A comprehensive proposal for an automated ARM template testing script has been created in [SCRIPT_PROPOSAL.md](SCRIPT_PROPOSAL.md).

### Key Features

The proposed Python script would:

- **Interactive Setup**: First-run wizard with smart defaults and minimal user input
- **Zero Configuration**: Automatic Git branch detection and artifact location URL construction
- **Azure CLI Native**: All operations via `az` commands for compatibility and transparency
- **Parallel Testing**: Deploy multiple scenarios simultaneously to reduce test time by 70%+
- **Pre-Deployment Validation**: Catch errors before expensive deployments with what-if analysis
- **Cost Visibility**: Estimate and track deployment costs with configurable limits
- **Intelligent Cleanup**: Multiple cleanup modes (immediate, on-success, manual, scheduled)
- **Comprehensive Reporting**: Markdown/HTML reports with historical tracking

### Implementation Approach

The script is designed in **10 implementation phases**:

1. **Foundation** - Interactive setup wizard and configuration management
2. **Core Engine** - Git integration and parameter file generation
3. **Validation** - Template validation and cost estimation
4. **Resource Management** - Resource group lifecycle with smart naming
5. **Deployment** - Parallel deployment orchestration
6. **Testing** - Neo4j connectivity testing and validation
7. **Cleanup** - Intelligent resource cleanup and orphan detection
8. **Reporting** - Report generation and comprehensive logging
9. **CLI Interface** - User-friendly command structure
10. **Advanced Features** - Cost tracking, template diffing, performance monitoring

### Directory Structure

The deployment tools reside in `deployments/` with all working files in `deployments/.arm-testing/`:
- `deployments/neo4j-deploy.py` - Main deployment and testing script
- `deployments/pyproject.toml` - Python project configuration with uv
- `deployments/.arm-testing/config/` - User settings and scenario definitions
- `deployments/.arm-testing/state/` - Active deployment tracking
- `deployments/.arm-testing/params/` - Generated parameter files
- `deployments/.arm-testing/results/` - Test outputs and reports
- `deployments/.arm-testing/logs/` - Execution logs
- `deployments/.arm-testing/cache/` - Downloaded binaries

The `.arm-testing/` directory is already in the repository `.gitignore`.

### Smart Defaults

The script uses intelligent defaults for:
- Resource group names: `neo4j-test-{scenario}-{timestamp}`
- Deployment names with timestamps
- Azure resource tags for tracking and cleanup
- Cost-effective VM sizes for testing
- Automatic password generation

### Comparison to Current Process

| Aspect | Current | Proposed |
|--------|---------|----------|
| Setup | Manual editing | Interactive wizard |
| Branch detection | Manual | Automatic |
| Validation | None | Pre-deployment + what-if |
| Parallel testing | No | Yes (configurable) |
| Output capture | Manual | Automatic |
| Testing | Manual | Automated |
| Cleanup | Manual | Multiple modes |
| Reporting | None | Comprehensive |
| Error handling | Fail and stop | Graceful + continue |

See [SCRIPT_PROPOSAL.md](SCRIPT_PROPOSAL.md) for complete details including all modules, phases, and implementation specifications

---

## Summary

This guide provides:
- Prerequisites for local testing
- Detailed understanding of template resources and parameters
- Current manual testing process with step-by-step instructions
- 2024-2025 ARM template best practices
- Reference to comprehensive Python script proposal in [SCRIPT_PROPOSAL.md](SCRIPT_PROPOSAL.md)

For automated testing implementation details, see [SCRIPT_PROPOSAL.md](SCRIPT_PROPOSAL.md) which describes a phased approach to building a testing script that addresses all limitations of the current process while incorporating modern ARM deployment best practices.
