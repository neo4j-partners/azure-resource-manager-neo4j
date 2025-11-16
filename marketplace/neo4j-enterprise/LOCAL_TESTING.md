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

### Overview

Create a Python script (`test_arm_template.py`) that automates the entire testing lifecycle with best practices built in. This would significantly improve upon the current shell scripts.

### What Already Exists (Resources to Leverage)

1. **ARM Template Files**
   - `mainTemplate.json` - The template to deploy
   - `parameters.json` - Base parameter file with defaults
   - `createUiDefinition.json` - Could be validated for consistency

2. **Shell Scripts**
   - `deploy.sh` - Basic deployment logic (to be replaced)
   - `delete.sh` - Cleanup logic (to be replaced)

3. **External Testing Tool**
   - `neo4jtester` - Binary from GitHub for validating deployments
   - Used by GitHub Actions workflows

4. **GitHub Actions Workflows**
   - `.github/workflows/enterprise.yml` - Reference implementation
   - Shows parameter combinations and testing patterns

### What Needs to Be Created

The Python script would need to implement these components from scratch:

#### 1. Configuration Management Module

**Description**: A YAML or JSON configuration file defining test scenarios.

**Purpose**:
- Define multiple test configurations (standalone, cluster, different versions)
- Specify which scenarios to run
- Set timeout values, locations, VM sizes
- Define cost limits per scenario

**Example structure** (conceptual):
```yaml
scenarios:
  - name: standalone-v5
    nodeCount: 1
    graphDatabaseVersion: "5"
    vmSize: Standard_E4s_v5

  - name: cluster-v5
    nodeCount: 3
    graphDatabaseVersion: "5"
    vmSize: Standard_E8s_v5
```

#### 2. Git Branch Detection Module

**Description**: Automatically detect current Git branch and construct artifact location URL.

**Purpose**:
- Read current branch from Git repository
- Construct `_artifactsLocation` URL automatically
- Override for testing specific branches
- Validate that scripts exist at the constructed URL

**Benefits**: Eliminates manual parameter file editing for branch testing.

#### 3. Parameter File Generation Module

**Description**: Dynamically create parameter files from test scenarios.

**Purpose**:
- Start with base `parameters.json`
- Merge scenario-specific overrides
- Inject `_artifactsLocation` automatically
- Generate secure random passwords (or retrieve from environment)
- Validate parameter combinations (e.g., read replicas only for 4.4)

**Output**: Temporary parameter files like `params-standalone-v5-20250116-143022.json`

#### 4. Pre-Deployment Validation Module

**Description**: Run ARM template validation and what-if analysis.

**Purpose**:
- Execute `az deployment group validate` for each scenario
- Run what-if analysis and parse results
- Estimate costs based on resource types and VM sizes
- Fail fast if validation errors detected
- Display resource changes before deployment

**Benefits**: Catches errors before expensive deployment starts.

#### 5. Resource Group Lifecycle Manager

**Description**: Create, tag, and manage resource groups.

**Purpose**:
- Generate unique resource group names with timestamps
- Create resource groups with standardized tags:
  - `purpose=automated-testing`
  - `scenario=<scenario-name>`
  - `branch=<git-branch>`
  - `created=<timestamp>`
  - `expires=<expiration-date>`
  - `owner=<git-user-email>`
- Track all created resource groups in a local state file
- Support querying which resource groups are currently active

**Benefits**: Better organization and cleanup tracking.

#### 6. Parallel Deployment Orchestrator

**Description**: Deploy multiple scenarios simultaneously with `--no-wait`.

**Purpose**:
- Launch multiple deployments in parallel (configurable max parallelism)
- Track deployment progress for all in-flight deployments
- Display real-time status dashboard in terminal
- Handle failures without blocking other deployments
- Implement timeout per deployment (default 30 minutes)

**Benefits**: Reduces total test time from hours to minutes when testing multiple configurations.

#### 7. Deployment Monitoring Module

**Description**: Poll deployment status and display progress.

**Purpose**:
- Query `az deployment group show` periodically for status
- Parse and display current deployment phase
- Show percentage complete if available
- Detect and report errors immediately
- Stream deployment operation details on failure

**Benefits**: Better visibility into long-running deployments.

#### 8. Output Extraction and Storage Module

**Description**: Capture deployment outputs and save structured data.

**Purpose**:
- Extract all template outputs (URLs, usernames)
- Save to JSON file: `outputs-<scenario>-<timestamp>.json`
- Parse URLs for automated testing
- Generate human-readable summary report
- Store in results directory with deployment name

**Benefits**: Enables automated testing and preserves deployment metadata.

#### 9. Neo4j Connection Testing Module

**Description**: Automated connectivity and functionality testing.

**Purpose**:
- Download `neo4jtester` binary if not cached locally
- Extract connection URI from deployment outputs
- Convert HTTP URLs to Neo4j protocol URIs (neo4j://)
- Execute neo4jtester with correct parameters
- Capture and parse test results
- Optionally run additional Cypher queries via Python driver

**Benefits**: Validates that deployment is functionally working, not just provisioned.

#### 10. Advanced Validation Module (Optional)

**Description**: Run deeper integration tests beyond basic connectivity.

**Purpose**:
- For cluster deployments, verify all nodes are online
- Test plugin functionality (GDS, Bloom) if enabled
- Execute sample workloads (CRUD operations, queries)
- Verify cluster can handle failover
- Check performance baselines
- Validate security configurations (open ports, SSL)

**Benefits**: Catches functional issues that basic testing misses.

#### 11. Cleanup and Resource Management Module

**Description**: Intelligent resource cleanup with safety checks.

**Purpose**:
- Track all created resources in local state file
- Support cleanup modes:
  - Immediate: Delete after each test
  - On-success: Delete only if tests pass
  - Manual: Keep for investigation
  - Scheduled: Delete after N hours
- Query Azure for orphaned resources matching tags
- Implement safety confirmation for production subscriptions
- Generate cleanup reports showing deleted resources

**Benefits**: Prevents accidental cost accumulation from forgotten resources.

#### 12. Reporting and Logging Module

**Description**: Comprehensive logging and test reporting.

**Purpose**:
- Log all operations to timestamped log files
- Generate HTML or Markdown test reports with:
  - Which scenarios ran
  - Pass/fail status for each
  - Deployment duration
  - Resource costs (estimated)
  - Error details with stack traces
  - Links to Azure portal for failed deployments
- Support CI/CD integration (JUnit XML output)
- Track historical test runs for trend analysis

**Benefits**: Enables debugging failed tests and tracking deployment reliability over time.

#### 13. Cost Tracking Module

**Description**: Monitor and report deployment costs.

**Purpose**:
- Query Azure Cost Management API
- Track costs per resource group
- Compare actual costs vs estimates
- Alert if costs exceed thresholds
- Generate cost summary in reports
- Support cost allocation by scenario/branch

**Benefits**: Visibility into testing costs and budget control.

#### 14. Interactive CLI Interface

**Description**: User-friendly command-line interface.

**Purpose**:
- Command structure:
  - `python test_arm_template.py validate` - Validate templates only
  - `python test_arm_template.py deploy --scenario standalone-v5` - Deploy single scenario
  - `python test_arm_template.py deploy --all` - Deploy all scenarios
  - `python test_arm_template.py test <deployment-name>` - Test existing deployment
  - `python test_arm_template.py cleanup --auto` - Cleanup based on tags
  - `python test_arm_template.py status` - Show active deployments
  - `python test_arm_template.py report <deployment-name>` - Generate report
- Interactive prompts for confirmations
- Colorized terminal output
- Progress bars for long operations
- Dry-run mode for safe testing

**Benefits**: Approachable interface for developers with varying Azure experience.

#### 15. Configuration File Templates

**Description**: Example configuration files to get started.

**Purpose**:
- `test-scenarios.example.yaml` - Sample test configurations
- `.env.example` - Environment variable template
- Document all configuration options
- Include presets for common scenarios

**Benefits**: Reduces setup friction for new users.

### Dependencies and Libraries Needed

The Python script would require these packages:

1. **Azure SDK for Python** (`azure-cli-core`, `azure-mgmt-resource`)
   - Purpose: Deploy templates, query resources, manage deployments

2. **PyYAML** or **tomli**
   - Purpose: Parse configuration files

3. **GitPython**
   - Purpose: Detect current branch, get repository information

4. **neo4j-driver** (official Python driver)
   - Purpose: Advanced Neo4j testing beyond neo4jtester

5. **rich** or **click**
   - Purpose: Beautiful terminal UI, progress bars, colored output

6. **jinja2**
   - Purpose: Generate HTML reports from templates

7. **pytest** (optional)
   - Purpose: If building test framework integration

8. **requests**
   - Purpose: Download neo4jtester binary, validate URLs

9. **python-dotenv**
   - Purpose: Load environment variables from `.env` file

10. **tabulate**
    - Purpose: Format table output in terminal

### Integration Points

**With existing infrastructure:**

1. **Parameters.json** - Read as base template, merge with scenario configs
2. **GitHub Actions** - Could invoke this script instead of inline bash
3. **Neo4jtester** - Download and execute, parse output
4. **Azure CLI** - Shell out to `az` commands or use SDK
5. **Git Repository** - Read branch, validate artifact URLs

### Script Architecture (High Level)

**Conceptual flow:**

```
1. Parse command-line arguments
2. Load configuration file (test scenarios)
3. Detect Git branch
4. For each scenario:
   a. Generate parameter file with _artifactsLocation
   b. Validate template syntax
   c. Run what-if analysis
   d. Estimate costs
5. If validation passes:
   a. Create resource groups with tags
   b. Launch deployments in parallel (max N concurrent)
   c. Monitor deployment progress with status dashboard
6. When deployments complete:
   a. Extract outputs
   b. Run neo4jtester for validation
   c. Execute additional Neo4j tests
   d. Generate test report
7. Cleanup (based on mode):
   a. Delete successful deployments (optional)
   b. Keep failed deployments for debugging
   c. Tag resources for later cleanup
8. Display summary:
   a. Pass/fail for each scenario
   b. Total duration
   c. Estimated costs
   d. Links to reports and logs
```

### Error Handling Requirements

**The script needs to gracefully handle:**

1. **Azure quota exceeded** - Detect and report quota issues
2. **Deployment timeouts** - Fail deployments exceeding time limits
3. **Partial failures** - Continue testing other scenarios
4. **Network issues** - Retry transient failures
5. **Invalid parameters** - Validate before deployment
6. **Missing permissions** - Clear error messages
7. **Branch script 404s** - Validate artifact location before deploy
8. **Concurrent deployment limits** - Respect Azure subscription limits

### State Management

**The script should maintain state in:**

1. **Local state file** (`test_state.json`)
   - Active deployments
   - Resource group names
   - Deployment start times
   - Scenario configurations used

2. **Results directory** (`test-results/`)
   - Deployment outputs
   - Test reports
   - Log files
   - Screenshots (if web testing added)

3. **Cache directory** (`cache/`)
   - Downloaded neo4jtester binary
   - Parameter file templates
   - Previous deployment metadata

### Safety Features

**Critical safety mechanisms:**

1. **Subscription detection** - Warn if deploying to production subscription
2. **Cost limit checks** - Abort if estimated costs exceed threshold
3. **Confirmation prompts** - Require confirmation for destructive operations
4. **Resource tagging** - All resources tagged as test resources
5. **Orphan detection** - Find resources without proper tags
6. **Dry-run mode** - Preview all actions without execution
7. **Rollback capability** - Delete resources if deployment fails

### Future Enhancements

**Potential additions:**

1. **Azure DevOps integration** - Publish test results to ADO
2. **Slack/Teams notifications** - Alert on test completion
3. **Performance benchmarking** - Track deployment and query performance over time
4. **Template diffing** - Compare template versions before deployment
5. **Multi-subscription testing** - Test across dev/staging subscriptions
6. **Chaos testing** - Intentionally fail resources to test resilience
7. **Compliance checking** - Validate security and compliance policies
8. **Resource optimization** - Suggest cheaper VM sizes for equivalent performance

### Documentation Needed

**To accompany the script:**

1. **README.md** - Overview, installation, quick start
2. **CONFIGURATION.md** - Detailed configuration options
3. **SCENARIOS.md** - Example test scenarios and when to use them
4. **TROUBLESHOOTING.md** - Common errors and solutions
5. **CONTRIBUTING.md** - How to add new scenarios or features

### Success Metrics

**The script would be successful if it:**

1. Reduces deployment testing time by 70%+ (via parallel execution)
2. Eliminates manual parameter editing errors
3. Catches template errors pre-deployment via validation
4. Provides clear test pass/fail results
5. Enables running full test suite before every PR
6. Prevents forgotten resource cleanup
7. Makes testing accessible to developers without deep Azure knowledge

### Comparison to Current Process

| Aspect | Current (Shell Scripts) | Proposed (Python Script) |
|--------|------------------------|--------------------------|
| Branch detection | Manual parameter file edit | Automatic |
| Validation | None | Pre-deployment validation + what-if |
| Parallel testing | Not supported | Up to N scenarios in parallel |
| Output capture | Manual `az` commands | Automatic extraction + storage |
| Testing | Manual or copy/paste commands | Automated with neo4jtester + Cypher |
| Cleanup | Manual script invocation | Multiple modes (auto/scheduled/manual) |
| Reporting | None | HTML/Markdown reports + logs |
| Error handling | Script fails | Graceful handling + continue |
| Cost visibility | None | Estimation + tracking |
| Multi-scenario | Run script multiple times | Single command for all scenarios |
| State tracking | None | Local state file + Azure tags |
| Documentation | Minimal | Comprehensive + examples |

---

## Summary

This guide provides:
- Prerequisites for local testing
- Detailed understanding of template resources and parameters
- Current manual testing process with step-by-step instructions
- 2024-2025 ARM template best practices
- Comprehensive Python script proposal to automate and improve testing

The proposed Python script would address all limitations of the current process while incorporating modern ARM deployment best practices, saving significant time and reducing errors in the testing workflow.
