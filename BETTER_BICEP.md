# Azure Bicep Template Review - Best Practices Analysis

**Template**: `marketplace/neo4j-enterprise/mainTemplate.bicep`
**Review Date**: 2025-11-17
**Reviewer**: Based on Microsoft Learn official guidance and Azure community best practices

---

## Executive Summary

The current Bicep template is **functional and well-structured** for a monolithic deployment, but has opportunities for improvement in several areas:

- ✅ **Good**: Uses cloud-init via `loadTextContent()`, proper resource dependencies, secure parameters
- ⚠️ **Needs Attention**: Outdated API versions, no modularity, missing validation decorators
- 🔴 **Critical**: No linter configuration, monolithic structure prevents reusability

**Overall Grade**: B- (Functional but not following current best practices)

---

## 1. API Versions ⚠️

### Current State

```
Microsoft.Compute/virtualMachineScaleSets@2018-06-01  ❌ 6 years old
Microsoft.Network/networkSecurityGroups@2022-07-01   ⚠️  2+ years old
Microsoft.Network/virtualNetworks@2022-07-01         ⚠️  2+ years old
Microsoft.Network/loadBalancers@2022-05-01           ⚠️  2+ years old
```

### Microsoft Guidance

> "It's a good idea to use a recent API version for each resource. New features in Azure services are sometimes available only in newer API versions."
>
> Source: [Bicep Best Practices - Microsoft Learn](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/best-practices)

The Bicep linter includes a `use-recent-api-versions` rule with default threshold of 730 days (2 years).

### Recommendation

**Update to latest stable API versions:**

```bicep
Microsoft.Compute/virtualMachineScaleSets@2023-09-01        // Latest stable
Microsoft.Network/networkSecurityGroups@2023-11-01          // Latest stable
Microsoft.Network/virtualNetworks@2023-11-01                // Latest stable
Microsoft.Network/loadBalancers@2023-11-01                  // Latest stable
Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31 // Latest stable
```

**Impact**: Low risk - Generally backwards compatible, enables access to newer features

**Reference**:
- [Linter Rule - Use Recent API Versions](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/linter-rule-use-recent-api-versions)
- [Azure Resource Provider API Versions](https://learn.microsoft.com/en-us/azure/templates/)

---

## 2. Linter Configuration 🔴

### Current State

**No `bicepconfig.json` file exists in the repository.**

### Microsoft Guidance

> "The Bicep linter checks Bicep files for syntax errors and best practice violations. Create a bicepconfig.json file with your custom settings."
>
> Source: [Use Bicep Linter - Microsoft Learn](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/linter)

### Recommendation

**Create `marketplace/neo4j-enterprise/bicepconfig.json`:**

```json
{
  "analyzers": {
    "core": {
      "enabled": true,
      "verbose": true,
      "rules": {
        "no-hardcoded-env-urls": {
          "level": "warning"
        },
        "no-unused-params": {
          "level": "warning"
        },
        "no-unused-vars": {
          "level": "warning"
        },
        "prefer-interpolation": {
          "level": "warning"
        },
        "secure-parameter-default": {
          "level": "error"
        },
        "simplify-interpolation": {
          "level": "warning"
        },
        "use-recent-api-versions": {
          "level": "warning",
          "maxAllowedAgeInDays": 730
        },
        "use-resource-id-functions": {
          "level": "warning"
        },
        "use-stable-resource-identifiers": {
          "level": "warning"
        },
        "outputs-should-not-contain-secrets": {
          "level": "error"
        }
      }
    }
  }
}
```

**Impact**: High value - Catches issues during development, enforces consistency

**Reference**: [Bicep Linter Settings](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/bicep-config-linter)

---

## 3. Modularity 🔴

### Current State

**Monolithic template** with 560 lines containing networking, compute, load balancer, and identity resources all in one file.

### Microsoft Guidance

> "Large, monolithic Bicep files can quickly become unwieldy. Breaking your code into smaller, reusable modules improves readability, maintainability, and reusability."
>
> Source: [Bicep Best Practices - Modularity](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/best-practices)

### Current Structure Problems

1. **Cannot reuse** components (e.g., networking) across different deployments
2. **Difficult to test** individual components in isolation
3. **Hard to maintain** as template grows with new features
4. **Violates separation of concerns** - networking mixed with compute

### Recommended Module Structure

```
marketplace/neo4j-enterprise/
├── main.bicep                          # Orchestrator (calls modules)
├── bicepconfig.json                    # Linter configuration
├── modules/
│   ├── networking/
│   │   ├── nsg.bicep                   # Network Security Group
│   │   └── vnet.bicep                  # Virtual Network
│   ├── compute/
│   │   └── vmss.bicep                  # VM Scale Set (reusable)
│   ├── loadbalancer/
│   │   └── lb.bicep                    # Load Balancer
│   └── identity/
│       └── managed-identity.bicep      # User Assigned Identity
└── parameters/
    ├── parameters.json                 # Default parameters
    └── parameters.prod.json            # Production overrides
```

**Benefits:**
- Each module is independently testable
- Modules can be versioned separately
- Easier to review changes (smaller diffs)
- Follows Azure Verified Modules (AVM) pattern

**Impact**: High - Major refactoring but significantly improves maintainability

**Reference**:
- [Bicep Modules](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/modules)
- [Azure Verified Modules](https://aka.ms/avm)

---

## 4. Parameter Validation ⚠️

### Current State

Parameters lack comprehensive validation decorators and descriptions.

### Issues Found

| Parameter | Missing | Recommendation |
|-----------|---------|----------------|
| `adminPassword` | `@minLength`, `@description` | Add length constraints and description |
| `vmSize` | `@description`, validation | Document valid sizes, add allowed list or description |
| `diskSize` | `@minValue`, `@maxValue`, `@description` | Add realistic constraints (e.g., 32-4096) |
| `location` | `@description` | Explain when to override default |
| `graphDataScienceLicenseKey` | Default value | Should default to empty string, not 'None' |
| `bloomLicenseKey` | `@secure()`, default | Should be secure and have default |

### Microsoft Guidance

> "It's a good practice to provide descriptions for your parameters. Try to make the descriptions helpful, providing important information about what the template needs."
>
> "It's a good practice to specify the minimum and maximum character length for parameters that control naming."
>
> Source: [Bicep Parameters Best Practices](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/parameters)

### Recommended Improvements

**Example - Enhanced Parameter Definitions:**

```bicep
@description('Administrator password for Neo4j. Must be at least 8 characters with complexity requirements.')
@minLength(8)
@maxLength(128)
@secure()
param adminPassword string

@description('Azure VM size for cluster nodes. See https://learn.microsoft.com/azure/virtual-machines/sizes')
@allowed([
  'Standard_D4s_v3'
  'Standard_D8s_v3'
  'Standard_D16s_v3'
  'Standard_D32s_v3'
  'Standard_E4s_v3'
  'Standard_E8s_v3'
])
param vmSize string

@description('Data disk size in GB. Must be between 32 GB and 4096 GB (4 TB).')
@minValue(32)
@maxValue(4096)
param diskSize int

@description('Azure region for deployment. Defaults to resource group location.')
@metadata({
  tipForUsers: 'Override only if deploying to different region than resource group'
})
param location string = resourceGroup().location

@description('Graph Data Science license key. Leave empty for evaluation or if not using GDS.')
@secure()
param graphDataScienceLicenseKey string = ''

@description('Bloom license key. Leave empty for evaluation or if not using Bloom.')
@secure()
param bloomLicenseKey string = ''
```

**Benefits:**
- Better Azure Portal UX (descriptions show as tooltips)
- Prevents invalid deployments before they start
- Self-documenting template
- Catches errors early

**Impact**: Medium - Easy to implement, significant UX improvement

**Reference**: [Parameter Decorators](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/parameters)

---

## 5. Naming Conventions ⚠️

### Current State

**Good:**
- Uses `camelCase` for variables and parameters ✅
- Uses `uniqueString()` for uniqueness ✅
- Uses Azure naming prefixes (nsg-, vnet-, vmss-) ✅

**Needs Improvement:**
- Inconsistent resource type prefixes
- Location embedded in every resource name (verbose)
- No centralized naming module

### Microsoft Guidance

> "Use good naming for parameter declarations. Good names make your templates easy to read and understand."
>
> "Use string interpolation to generate resource names as variables."
>
> Source: [Name Generation Patterns](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/patterns-name-generation)

### Current Naming Pattern

```bicep
var networkSGName = 'nsg-neo4j-${location}-${resourceSuffix}'
var vnetName = 'vnet-neo4j-${location}-${resourceSuffix}'
var loadBalancerName = 'lb-neo4j-${location}-${resourceSuffix}'
```

### Recommended Improvement

**Option 1: Naming Module (Best Practice)**

Create `modules/naming.bicep`:

```bicep
// Centralized naming convention following Azure Cloud Adoption Framework
param workloadName string = 'neo4j'
param environment string = 'prod'
param location string
param instance string = '001'

var locationShort = {
  eastus: 'eus'
  westus: 'wus'
  centralus: 'cus'
  eastus2: 'eus2'
  // ... other regions
}

output networkSecurityGroup string = 'nsg-${workloadName}-${environment}-${locationShort[location]}-${instance}'
output virtualNetwork string = 'vnet-${workloadName}-${environment}-${locationShort[location]}-${instance}'
output loadBalancer string = 'lb-${workloadName}-${environment}-${locationShort[location]}-${instance}'
output vmss string = 'vmss-${workloadName}-${environment}-${locationShort[location]}-${instance}'
```

**Option 2: Simplified Pattern (Good Enough)**

```bicep
// Simplified naming with optional environment parameter
@description('Environment name (dev, test, prod)')
@allowed(['dev', 'test', 'prod'])
param environment string = 'prod'

var namingPrefix = 'neo4j-${environment}'
var networkSGName = 'nsg-${namingPrefix}-${resourceSuffix}'
var vnetName = 'vnet-${namingPrefix}-${resourceSuffix}'
var loadBalancerName = 'lb-${namingPrefix}-${resourceSuffix}'
```

**Impact**: Low-Medium - Improves readability and follows Azure CAF standards

**Reference**:
- [Azure Naming Conventions](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming)
- [Community Naming Module](https://github.com/nianton/azure-naming)

---

## 6. Resource Dependencies ✅

### Current State

**Good:** Template uses implicit dependencies through symbolic names.

```bicep
resource vnet 'Microsoft.Network/virtualNetworks@2022-07-01' = {
  properties: {
    subnets: [
      {
        properties: {
          networkSecurityGroup: {
            id: networkSG.id  // ✅ Implicit dependency
          }
        }
      }
    ]
  }
}
```

### Microsoft Guidance

> "Use symbolic names to create an implicit dependency instead of using dependsOn. Bicep can infer dependencies from references to symbolic names."
>
> Source: [Bicep Best Practices - Dependencies](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/best-practices)

### Minor Issue

Line 550-552: Explicit `dependsOn` used for read replica VMSS:

```bicep
dependsOn: [
  vmScaleSets
]
```

**While not wrong**, this could be implicit by referencing a property from `vmScaleSets` resource.

**Impact**: Very Low - Current approach is acceptable but could be cleaner

---

## 7. Variables and Expressions ⚠️

### Current State

Some complex logic embedded inline, reducing readability.

### Issues

**Line 427-429: Inline conditional logic**
```bicep
loadBalancerBackendAddressPools: (loadBalancerCondition
  ? loadBalancerBackendAddressPools
  : null)
```

**Line 69-81: Deeply nested replace() calls**
```bicep
var cloudInitData = replace(
  replace(
    replace(
      replace(
        replace(cloudInitTemplate, '\\${unique_string}', deploymentUniqueId),
        '\\${location}', location
      ),
      '\\${admin_password}', adminPassword
    ),
    '\\${license_agreement}', licenseAgreement
  ),
  '\\${node_count}', string(nodeCount)
)
```

### Microsoft Guidance

> "Extract complex expressions into variables to make your code more readable."
>
> Source: [Bicep Best Practices](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/best-practices)

### Recommended Improvements

**Extract backend pool logic:**

```bicep
// More readable with extracted variable
var backendPoolsOrNull = loadBalancerCondition ? loadBalancerBackendAddressPools : null

// Then in resource:
loadBalancerBackendAddressPools: backendPoolsOrNull
```

**Use reduce pattern for multiple replacements:**

While Bicep doesn't have reduce(), consider a user-defined function or simplify the pattern:

```bicep
// Alternative: Use object for substitutions
var cloudInitSubstitutions = {
  '\\${unique_string}': deploymentUniqueId
  '\\${location}': location
  '\\${admin_password}': adminPassword
  '\\${license_agreement}': licenseAgreement
  '\\${node_count}': string(nodeCount)
}

// Then reference in comments that these are applied
// (actual implementation would still need nested replace, but intent is clearer)
```

**Impact**: Low - Readability improvement only

---

## 8. Comments and Documentation ⚠️

### Current State

Minimal inline comments. Good comments at lines 438 and 94, but most resources lack explanation.

### Microsoft Guidance

> "Good documentation helps users understand what the template does and how to use it effectively."

### Missing Documentation

- No file header explaining template purpose
- No explanation of deployment modes (standalone vs cluster)
- No documentation of cloud-init substitution pattern
- Resource blocks lack comments explaining purpose

### Recommended Additions

**File Header:**

```bicep
// ==============================================================================
// Neo4j Enterprise Azure Deployment Template
// ==============================================================================
//
// Description:
//   Deploys Neo4j Enterprise Edition on Azure using VM Scale Sets.
//   Supports both standalone (nodeCount=1) and cluster (nodeCount=3-10) modes.
//   Uses cloud-init for configuration instead of custom script extensions.
//
// Architecture:
//   - Standalone: Single VMSS instance with public IP
//   - Cluster: 3-10 VMSS instances with load balancer
//   - Optional: Read replicas for Neo4j 4.4 only
//
// Version: 1.0.0
// Last Updated: 2025-11-17
// ==============================================================================

// ============================================================
// PARAMETERS
// ============================================================

// ... parameters here
```

**Resource Documentation:**

```bicep
// Network Security Group - Controls inbound/outbound traffic
// Ports: 22 (SSH), 7474 (HTTP), 7473 (HTTPS), 7687 (Bolt)
// Cluster: 5000 (Raft), 6000 (Discovery V2) - VirtualNetwork only
resource networkSG 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  // ...
}
```

**Impact**: Low - Improves maintainability and onboarding

---

## 9. Security Best Practices ✅ / ⚠️

### What's Good ✅

1. **Secure parameters**: `adminPassword`, `bloomLicenseKey` use `@secure()` decorator
2. **NSG restrictions**: Cluster ports restricted to VirtualNetwork only
3. **No hardcoded secrets**: Passwords passed as parameters
4. **Disk encryption**: Using Azure Managed Disks (encrypted by default)

### What Could Be Better ⚠️

1. **Key Vault integration**: Secrets should come from Azure Key Vault, not parameters
2. **Output exposure**: Outputs include URLs which is fine, but ensure no secrets leak
3. **SSH access**: Port 22 open to Internet (priority 100) - should be restricted
4. **No disk encryption set**: Not using customer-managed keys (CMK)

### Microsoft Guidance

> "Don't save sensitive data (passwords, connection strings, etc.) in parameter files. Retrieve these values from Azure Key Vault."
>
> Source: [Bicep Secrets Best Practices](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/scenarios-secrets)

### Recommendations

**1. Key Vault Integration:**

```bicep
// Reference existing Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
  scope: resourceGroup(keyVaultResourceGroup)
}

// Get secret from Key Vault
var adminPassword = keyVault.getSecret('neo4j-admin-password')
```

**2. Restrict SSH Access:**

```bicep
@description('CIDR range allowed for SSH access. Use your organization IP range.')
param allowedSSHSourceAddress string = '0.0.0.0/0'  // Default allows all, force user to set

{
  name: 'SSH'
  properties: {
    sourceAddressPrefix: allowedSSHSourceAddress  // ✅ Parameterized
    // ...
  }
}
```

**3. Customer-Managed Keys (Optional):**

```bicep
resource diskEncryptionSet 'Microsoft.Compute/diskEncryptionSets@2023-04-02' = {
  name: 'des-neo4j-${resourceSuffix}'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    activeKey: {
      keyUrl: keyVaultKey.properties.keyUriWithVersion
    }
  }
}
```

**Impact**:
- Key Vault: High - Required for production
- SSH restriction: High - Security hardening
- CMK: Low - Advanced feature, not required

**Reference**:
- [Use Azure Key Vault with Bicep](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/key-vault-parameter)
- [Azure Disk Encryption](https://learn.microsoft.com/en-us/azure/virtual-machines/disk-encryption-overview)

---

## 10. Outputs ✅

### Current State

**Good outputs:**

```bicep
output Neo4jBrowserURL string = uri('http://vm0.neo4j-${deploymentUniqueId}.${location}.cloudapp.azure.com:7474', '')
output Neo4jClusterBrowserURL string = loadBalancerCondition ? uri('http://${publicIp!.properties.ipAddress}:7474', '') : ''
output Username string = 'neo4j'
```

### Recommendations

**1. Add deployment metadata:**

```bicep
output deploymentInfo object = {
  mode: nodeCount == 1 ? 'standalone' : 'cluster'
  nodeCount: nodeCount
  version: graphDatabaseVersion
  licenseType: licenseType
  region: location
  deploymentId: deploymentUniqueId
}
```

**2. Add resource IDs for automation:**

```bicep
output vmssResourceId string = vmScaleSets.id
output vnetResourceId string = vnet.id
output loadBalancerResourceId string = loadBalancerCondition ? loadBalancer.id : ''
```

**3. Connection strings:**

```bicep
output boltConnectionString string = 'bolt://vm0.neo4j-${deploymentUniqueId}.${location}.cloudapp.azure.com:7687'
output clusterBoltConnectionString string = loadBalancerCondition ? 'bolt://${publicIp!.properties.ipAddress}:7687' : ''
```

**Impact**: Low-Medium - Improves automation and UX

---

## 11. Load Balancer Configuration ⚠️

### Issues Found

**Line 323-324: Minimal health probe configuration**

```bicep
numberOfProbes: 1
probeThreshold: 1
```

### Microsoft Guidance

Health probes should be configured with appropriate thresholds for production workloads.

### Recommendation

```bicep
{
  name: 'httpprobe'
  properties: {
    protocol: 'Http'
    port: 7474
    requestPath: '/'  // Consider '/db/system/cluster/available' for cluster-aware probe
    intervalInSeconds: 15  // Increased from 5 - less aggressive
    numberOfProbes: 2      // Increased from 1 - more reliable
    probeThreshold: 2      // More tolerance before marking unhealthy
  }
}
```

**Impact**: Medium - Improves stability and prevents false positives

**Reference**: [Load Balancer Health Probes](https://learn.microsoft.com/en-us/azure/load-balancer/load-balancer-custom-probe-overview)

---

## 12. Cloud-Init Integration ✅

### Current State

**Excellent approach** using `loadTextContent()`:

```bicep
var cloudInitStandalone = loadTextContent('../../scripts/neo4j-enterprise/cloud-init/standalone.yaml')
var cloudInitCluster = loadTextContent('../../scripts/neo4j-enterprise/cloud-init/cluster.yaml')
```

This is **better than** the old CustomScript extension approach because:
- ✅ Faster boot times (no download required)
- ✅ No external dependencies (GitHub)
- ✅ Embedded in template (single deployment artifact)
- ✅ Easier to version control

**No changes needed** - this is best practice for 2024+

**Reference**: [Bicep loadTextContent Function](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/bicep-functions-files#loadtextcontent)

---

## 13. Tags and Metadata ✅ / ⚠️

### Current State

**Good tagging on VMSS:**

```bicep
tags: {
  Neo4jVersion: graphDatabaseVersion
  Neo4jEdition: licenseType
  NodeCount: string(nodeCount)
  DeployedBy: 'arm-template'
  TemplateVersion: '1.0.0'
}
```

### Missing

Tags on other resources (NSG, VNet, Load Balancer, etc.)

### Recommendation

**Create common tags variable:**

```bicep
var commonTags = {
  Application: 'Neo4j'
  Version: graphDatabaseVersion
  Edition: licenseType
  DeployedBy: 'bicep-template'
  TemplateVersion: '1.0.0'
  Environment: environment  // Add environment parameter
  CostCenter: costCenter    // Add cost tracking
}

// Apply to all resources
resource networkSG 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: networkSGName
  location: location
  tags: commonTags  // ✅ Consistent tagging
  // ...
}
```

**Impact**: Low-Medium - Improves cost tracking and governance

**Reference**: [Azure Tagging Best Practices](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-tagging)

---

## Priority Recommendations

### 🔴 Critical (Do First)

1. **Create `bicepconfig.json`** - Enable linting and validation
2. **Update API versions** - Use latest stable versions (2023+)
3. **Add Key Vault integration** - Remove secrets from parameters
4. **Restrict SSH access** - Don't expose to entire Internet

### 🟡 Important (Do Soon)

5. **Break into modules** - Separate networking, compute, load balancer
6. **Add parameter descriptions** - Improve UX and documentation
7. **Improve health probes** - More reliable load balancer configuration
8. **Add comprehensive tagging** - Better governance and cost tracking

### 🟢 Nice to Have (Future)

9. **Improve naming conventions** - Use naming module pattern
10. **Extract complex expressions** - Better readability
11. **Add file header documentation** - Easier onboarding
12. **Add deployment metadata outputs** - Better automation

---

## Implementation Roadmap

### Phase 1: Quick Wins (1-2 hours)
- [ ] Create `bicepconfig.json`
- [ ] Update API versions to 2023-xx-xx
- [ ] Add parameter descriptions and validation decorators
- [ ] Add comprehensive tags to all resources

### Phase 2: Security Hardening (2-3 hours)
- [ ] Integrate Azure Key Vault for secrets
- [ ] Parameterize SSH source address restriction
- [ ] Improve load balancer health probes
- [ ] Add customer-managed keys (optional)

### Phase 3: Refactoring (1-2 days)
- [ ] Break template into modules (networking, compute, load balancer)
- [ ] Create centralized naming module
- [ ] Add comprehensive inline documentation
- [ ] Create separate parameter files (dev, test, prod)

### Phase 4: Advanced Features (Future)
- [ ] Add availability zone support
- [ ] Implement Blue/Green deployment pattern
- [ ] Add automated backup module
- [ ] Create CI/CD pipeline with linting

---

## References

### Official Microsoft Documentation

1. **Bicep Best Practices**
   https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/best-practices

2. **Bicep Linter Configuration**
   https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/linter

3. **Bicep Parameters**
   https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/parameters

4. **Bicep Modules**
   https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/modules

5. **Azure Naming Conventions**
   https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming

6. **Use Azure Key Vault with Bicep**
   https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/key-vault-parameter

7. **API Version Best Practices**
   https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/linter-rule-use-recent-api-versions

8. **Azure Verified Modules**
   https://aka.ms/avm

### Community Resources

9. **Rabobank - 5 Best Practices for Azure Bicep**
   https://rabobank.jobs/en/techblog/gijs-reijn-5-best-practices-for-using-azure-bicep/

10. **SQL Stad - Clean Bicep Code**
    https://sqlstad.nl/posts/2024/best-practices-for-writing-clean-bicep-code/

11. **Azure Naming Bicep Module**
    https://github.com/nianton/azure-naming

---

## Conclusion

The current `mainTemplate.bicep` is **functional and demonstrates good understanding** of Bicep fundamentals. The use of cloud-init with `loadTextContent()` is particularly well done and represents current best practices.

However, the template would benefit significantly from:
1. **Modernization** (API versions, linter configuration)
2. **Modularization** (breaking into reusable components)
3. **Security hardening** (Key Vault integration, restricted access)
4. **Documentation** (parameter descriptions, inline comments)

Implementing these recommendations will result in a template that is:
- ✅ More maintainable and testable
- ✅ More secure and production-ready
- ✅ More reusable across different environments
- ✅ Aligned with Microsoft and community best practices

**Recommendation**: Start with Phase 1 (Quick Wins) to get immediate benefits, then proceed with security hardening before any production deployment.
