# ARM Template Upgrade Support Analysis

**Date:** 2025-11-16
**Context:** Understanding how static tags affect upgrade scenarios

---

## Current Tag-Based Version Pinning

### How It Works Today

**Installation Flow (node4.sh:116-128):**
```bash
set_yum_pkg() {
    yumPkg="neo4j-enterprise"
    get_vmss_tags  # Read existing tag from VMSS

    if [[ -z "${taggedNeo4jVersion}" || "${taggedNeo4jVersion}" == "null" ]]; then
        # No tag exists - get latest from versions service
        get_latest_neo4j_version
        yumPkg="neo4j-enterprise-${latest_neo4j_version}"
    else
        # Tag exists - use tagged version
        yumPkg="neo4j-enterprise-${taggedNeo4jVersion}"
    fi
}
```

**After Installation:**
```bash
set_vmss_tags() {
    # Write actual installed version to tag
    installed_neo4j_version=$(/usr/bin/neo4j --version)
    az tag create --tags Neo4jVersion="${installed_neo4j_version}" ...
}
```

### Purpose
- **Version Consistency**: Ensures all VMs in VMSS install same Neo4j version
- **Scale-Out Support**: New VMs added to existing cluster install matching version
- **Re-deployment Safety**: Prevents accidental version changes

---

## Upgrade Scenarios: Reality Check

### Scenario 1: Initial Deployment (Marketplace)
**What happens:**
- Customer clicks "Deploy" in Azure Marketplace
- ARM template creates all resources
- VMs run installation scripts
- Neo4j cluster starts

**Current tag behavior:**
- Tag doesn't exist initially
- Scripts fetch latest version from versions.neo4j-templates.com
- After install, scripts write actual version to tag

**With static tags:**
- Tag exists from template (e.g., "5.23.0")
- Scripts would use tagged version
- **Result: SAME behavior, just clearer**

### Scenario 2: Scale Out (Add Nodes to Existing Cluster)
**What happens:**
- Customer increases VMSS instance count in Azure Portal
- New VMs are created from same VMSS definition
- New VMs run same installation scripts
- Must install SAME Neo4j version as existing nodes

**Current tag behavior:**
- ✅ Tag exists on VMSS (written by first deployment)
- ✅ New VMs read tag and install matching version
- ✅ Cluster maintains version consistency

**With static tags:**
- ✅ Tag exists from template
- ✅ New VMs read tag and install matching version
- ✅ **Result: WORKS THE SAME**

### Scenario 3: ARM Template Re-Deployment
**What happens:**
- Customer wants to change parameters (VM size, add plugin, etc.)
- Re-deploys ARM template with new parameters
- Azure updates VMSS definition
- **Question: Should this upgrade Neo4j?**

**Current tag behavior:**
- Template parameter: `graphDatabaseVersion: "5"`
- VMSS tag from previous deployment: `Neo4jVersion: "5.23.0"`
- Re-deployment doesn't change VMSS tag (tags persist)
- **Problem: Can't upgrade via template re-deployment!**

**With static tags:**
- Template parameter: `graphDatabaseVersion: "5.24.0"` (new version)
- Template overwrites tag: `Neo4jVersion: "5.24.0"`
- VMSS re-imaging would use new version
- **Result: BETTER upgrade support!**

### Scenario 4: Neo4j In-Place Upgrade
**What happens:**
- Customer runs Neo4j native upgrade process
- SSHs into VMs, runs `yum update neo4j-enterprise`
- Neo4j upgrades without VM re-creation
- **This is the RECOMMENDED upgrade path**

**Current tag behavior:**
- Tag shows old version (not updated by manual upgrade)
- Tag is now INCORRECT
- **Problem: Tags become stale**

**With static tags:**
- Tag shows template version
- Still not updated by manual upgrade
- **Same problem, but at least tag shows intent**

---

## The Truth About ARM Template "Upgrades"

### ARM Templates Are NOT Upgrade Tools

**Azure Resource Manager templates are for:**
- ✅ Initial deployment (infrastructure as code)
- ✅ Configuration changes (VM size, plugins, settings)
- ✅ Disaster recovery (redeploy infrastructure)

**ARM templates are NOT for:**
- ❌ Application upgrades (Neo4j version changes)
- ❌ Data migration (database upgrades)
- ❌ Zero-downtime updates

### Neo4j Upgrade Best Practices

**For Production Clusters:**
1. **Backup data** (snapshot disks or Neo4j backup)
2. **Use Neo4j's native upgrade process:**
   - Rolling upgrade for clusters (one node at a time)
   - Documented upgrade procedures
   - Preserves data and configuration
3. **Test in staging environment first**
4. **Monitor during upgrade**

**Neo4j Official Docs:**
- https://neo4j.com/docs/operations-manual/current/upgrade/
- Cluster rolling upgrade procedure
- Backup and restore procedures

### What ARM Templates CAN Do for Upgrades

**Blue-Green Deployment:**
```
1. Deploy new cluster with new version (separate resource group)
2. Migrate data from old to new cluster
3. Switch traffic to new cluster
4. Delete old cluster
```

This is:
- ✅ Safe (old cluster stays running during migration)
- ✅ Testable (validate new cluster before switching)
- ✅ Supported by ARM templates
- ❌ Requires data migration (not handled by ARM)

---

## Impact Analysis: Static Tags vs. Self-Tagging

### What BREAKS with Static Tags?

**Answer: Nothing of value**

1. **Initial Deployment:** Works identically
2. **Scale Out:** Works identically (maybe better - tag is clearer)
3. **ARM Re-Deployment:** Actually BETTER (can update version via template)
4. **In-Place Upgrade:** Not supported by either approach

### What IMPROVES with Static Tags?

1. **Clarity:** Tag shows template intent, not runtime state
2. **Upgrade Path:** Can change version via template re-deployment
3. **Simplicity:** Fewer moving parts, fewer failure modes
4. **Permissions:** Works with Contributor role

---

## The Right Way to Support Upgrades

### Option 1: Keep It Simple (Recommended)

**Static Tags + Clear Documentation**

**ARM Template:**
```json
{
  "type": "Microsoft.Compute/virtualMachineScaleSets",
  "tags": {
    "Neo4jTemplateVersion": "[parameters('graphDatabaseVersion')]",
    "Neo4jDeploymentMethod": "arm-template"
  }
}
```

**Installation Script:**
```bash
# Use template parameter, not tag lookup
NEO4J_VERSION="${graphDatabaseVersion}"  # Passed from ARM template
yum install -y "neo4j-enterprise-${NEO4J_VERSION}"
```

**Documentation:**
```markdown
## Upgrading Neo4j

### For version updates:
1. Use Neo4j's native upgrade process (recommended)
   - See: https://neo4j.com/docs/operations-manual/current/upgrade/

2. For infrastructure changes (VM size, etc.):
   - Re-deploy ARM template with updated parameters

3. For major version upgrades requiring new cluster:
   - Deploy new cluster (blue-green deployment)
   - Migrate data
   - Switch traffic
```

### Option 2: Hybrid Approach

**Use BOTH template tags AND runtime tags**

**Template provides intent:**
```json
"tags": {
  "Neo4jDesiredVersion": "[parameters('graphDatabaseVersion')]",
  "TemplateDeployedBy": "arm-marketplace"
}
```

**Scripts track actual state:**
```bash
# Read desired version from template tag
desired_version=$(az vmss show ... | jq -r '.tags.Neo4jDesiredVersion')

# Install desired version
yum install -y "neo4j-enterprise-${desired_version}"

# Write actual version to separate tag (no custom role needed!)
# Use Azure CLI from VM with system-assigned managed identity
# Grant "Tag Contributor" role at VMSS scope (not subscription!)
```

**Benefits:**
- ✅ Template shows intent
- ✅ Runtime tags show actual state
- ⚠️ Still needs managed identity permissions (but scoped to resource, not subscription)

### Option 3: External State Management

**Don't use Azure tags at all**

**Track versions externally:**
- Azure Monitor/Log Analytics (query actual Neo4j version)
- External configuration database
- Neo4j cluster status API

**Benefits:**
- ✅ No permission issues
- ✅ More reliable (queries actual state)
- ✅ Better for monitoring/alerting

**Implementation:**
```bash
# Installation script
NEO4J_VERSION="${graphDatabaseVersion}"
yum install -y "neo4j-enterprise-${NEO4J_VERSION}"

# Post-install: Report to external system
ACTUAL_VERSION=$(/usr/bin/neo4j --version)
curl -X POST "https://monitoring.example.com/api/clusters/${CLUSTER_ID}/version" \
     -d "{\"version\": \"${ACTUAL_VERSION}\", \"node\": \"${HOSTNAME}\"}"
```

---

## Recommended Solution for Testing + Production

### For Your Testing (localtests/)

**Use Static Tags:**
```json
"tags": {
  "Neo4jVersion": "[parameters('graphDatabaseVersion')]",
  "TestScenario": "automated-testing",
  "ManagedBy": "test-framework"
}
```

**Why:**
- ✅ Works with Contributor role
- ✅ Clear version tracking
- ✅ Test framework tracks everything in state files anyway
- ✅ Tests are deploy-validate-destroy (no upgrades)

### For Marketplace Production

**Static Tags + Documentation:**
```json
"tags": {
  "Neo4jVersion": "[parameters('graphDatabaseVersion')]",
  "DeploymentSource": "azure-marketplace",
  "SupportURL": "https://neo4j.com/support/"
}
```

**Plus README:**
```markdown
## Important: Upgrading Neo4j

This ARM template deploys the specified Neo4j version.

For upgrades, please use Neo4j's native upgrade procedures:
- Documentation: https://neo4j.com/docs/upgrade/
- Support: https://neo4j.com/support/

Re-deploying this template with a new version parameter is NOT
the recommended upgrade path for production clusters.
```

**Why:**
- ✅ Marketplace customers deploy once
- ✅ Upgrades are handled by Neo4j procedures
- ✅ ARM template is for infrastructure, not app upgrades
- ✅ Clear expectations set upfront

---

## Migration Path: Keeping Both Behaviors

### If You Want Maximum Compatibility

**Keep self-tagging but make it OPTIONAL:**

**ARM Template:**
```json
{
  "parameters": {
    "enableVmSelfTagging": {
      "type": "bool",
      "defaultValue": false,
      "metadata": {
        "description": "Enable VMs to self-tag (requires elevated permissions)"
      }
    }
  },
  "resources": [
    {
      "type": "Microsoft.Authorization/roleDefinitions",
      "condition": "[parameters('enableVmSelfTagging')]",
      "..."
    }
  ]
}
```

**Installation Script:**
```bash
if [[ "${enableVmSelfTagging}" == "true" ]]; then
  set_vmss_tags  # Write actual version
else
  echo "Self-tagging disabled, using template tags"
fi
```

**Benefits:**
- ✅ Testing can disable self-tagging (works with Contributor)
- ✅ Production can enable it if needed (with Owner permissions)
- ✅ Backward compatible
- ❌ More complexity

**Verdict:** Not worth it. Just remove self-tagging entirely.

---

## Code Changes for Proper Upgrade Support

### Enhanced Script Logic

**Instead of reading tags, use template parameter directly:**

**Current (node4.sh):**
```bash
set_yum_pkg() {
    yumPkg="neo4j-enterprise"
    get_vmss_tags  # ❌ Requires RBAC permissions
    if [[ -z "${taggedNeo4jVersion}" ]]; then
        get_latest_neo4j_version
        yumPkg="neo4j-enterprise-${latest_neo4j_version}"
    else
        yumPkg="neo4j-enterprise-${taggedNeo4jVersion}"
    fi
}
```

**Improved:**
```bash
set_yum_pkg() {
    # Use template parameter directly (passed via commandToExecute)
    NEO4J_VERSION="${graphDatabaseVersion}"  # e.g., "5" or "4.4"

    # If specific version not provided, get latest
    if [[ "${NEO4J_VERSION}" == "5" ]]; then
        get_latest_neo4j_5_version
        yumPkg="neo4j-enterprise-${latest_neo4j_version}"
    elif [[ "${NEO4J_VERSION}" == "4.4" ]]; then
        get_latest_neo4j_44_version
        yumPkg="neo4j-enterprise-${latest_neo4j_version}"
    else
        # Specific version provided
        yumPkg="neo4j-enterprise-${NEO4J_VERSION}"
    fi

    echo "Installing ${yumPkg}"
}
```

**Benefits:**
- ✅ No RBAC permissions needed
- ✅ Clearer logic (parameter is source of truth)
- ✅ Version consistency guaranteed
- ✅ Supports both "5" (latest 5.x) and "5.23.0" (specific version)

---

## Final Recommendation

### Short Answer: Static Tags DON'T Break Upgrades

**Because ARM templates aren't upgrade tools anyway.**

### What To Do

**1. For Testing (NOW):**
- Remove self-tagging
- Use static tags in template
- Update scripts to use template parameter
- Document that testing is deploy-destroy, no upgrades

**2. For Marketplace (NEXT):**
- Keep static tags approach
- Add clear upgrade documentation
- Point to Neo4j native upgrade docs
- Set expectations: ARM is for infrastructure, not app upgrades

**3. For Future (LATER):**
- Add Azure Monitor integration for version tracking
- Consider blue-green deployment guide
- Provide upgrade runbooks in docs

### What NOT To Do

❌ Don't over-engineer version tracking
❌ Don't try to make ARM templates handle data migration
❌ Don't promise upgrade support via ARM re-deployment
❌ Don't require Owner permissions for something tags can handle

---

## Testing the Change

### Verification Checklist

**Test 1: Fresh Deployment**
```bash
# Deploy with static tags
uv run test-arm.py deploy --scenario standalone-v5

# Verify:
# - VMSS has tag Neo4jVersion="5"
# - Neo4j installs correct version
# - No RBAC errors
```

**Test 2: Scale Out**
```bash
# After deployment, scale VMSS from 3 to 4 instances
az vmss scale --name <vmss> --new-capacity 4

# Verify:
# - New VM reads tag from VMSS
# - New VM installs same Neo4j version
# - Cluster stays healthy
```

**Test 3: Re-Deployment with Version Change**
```bash
# Re-deploy with new version parameter
az deployment group create \
  --parameters graphDatabaseVersion="5.24.0"

# Verify:
# - VMSS tag updates to 5.24.0
# - VMSS re-imaging would use new version
# - Existing VMs not affected (expected)
```

---

## Conclusion

**Static tags are BETTER for upgrades than self-tagging because:**

1. **Clarity:** Tag shows template intent, not stale runtime state
2. **Re-deployment:** Can actually update version via template
3. **Simplicity:** No RBAC complexity
4. **Truth:** ARM templates aren't upgrade tools anyway

**The right upgrade path is:**
- Neo4j native upgrade procedures (recommended)
- Blue-green deployment (for major changes)
- NOT ARM template re-deployment with data in place

**Remove self-tagging. It's solving a problem that doesn't exist.**
