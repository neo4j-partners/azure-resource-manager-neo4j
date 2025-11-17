# Bicep Development Standards

This document defines the development standards and conventions for Bicep templates in the Azure Neo4j deployment infrastructure.

## Table of Contents

- [General Principles](#general-principles)
- [File Organization](#file-organization)
- [Naming Conventions](#naming-conventions)
- [Parameter Guidelines](#parameter-guidelines)
- [Security Best Practices](#security-best-practices)
- [Resource Configuration](#resource-configuration)
- [Code Style](#code-style)
- [Documentation](#documentation)
- [Linter Configuration](#linter-configuration)

---

## General Principles

### Keep It Simple

- Prefer single main template with minimal modules over heavy modularization
- Only create modules when there's clear separation of concerns (e.g., cluster vs. standalone)
- Avoid unnecessary abstraction layers

### Follow Complete Cut-Over Requirements

- Make complete, atomic changes - no partial updates
- No compatibility layers or migration phases
- Direct replacements only - no wrapper functions
- Clean up old code completely - don't comment it out

### Security First

- **Never** include plain-text secrets in templates or parameters
- Use Azure Key Vault with Managed Identity for all secrets
- Use `@secure()` decorator for sensitive parameters
- Validate that outputs don't expose secrets

---

## File Organization

### Main Templates

```
marketplace/
├── neo4j-enterprise/
│   ├── mainTemplate.bicep           # Main Enterprise template
│   ├── cluster.bicep                # Cluster-specific module
│   ├── standalone.bicep             # Standalone-specific module
│   └── cloud-init/                  # Cloud-init configurations
│       ├── base.yaml
│       ├── cluster.yaml
│       └── replica.yaml
└── neo4j-community/
    ├── mainTemplate.bicep           # Main Community template (standalone only)
    └── cloud-init/
        └── standalone.yaml
```

### Configuration Files

```
Repository Root/
├── bicepconfig.json                 # Bicep linter configuration
├── scripts/
│   ├── pre-commit-bicep             # Pre-commit hook for validation
│   └── install-git-hooks.sh         # Hook installation script
└── docs/
    ├── BICEP_STANDARDS.md           # This document
    └── DEVELOPMENT_SETUP.md         # Setup instructions
```

---

## Naming Conventions

### Parameters

Use **camelCase** for parameter names:

```bicep
// Good
param storageAccountName string
param nodeCount int
param graphDatabaseVersion string

// Bad
param storage_account_name string
param NodeCount int
param graph-database-version string
```

### Variables

Use **camelCase** for variable names:

```bicep
// Good
var resourceTags = { ... }
var clusterNodes = [ ... ]
var neo4jVersion = '5.0'

// Bad
var ResourceTags = { ... }
var cluster_nodes = [ ... ]
var neo4j-version = '5.0'
```

### Resources

Use **camelCase** for resource symbolic names:

```bicep
// Good
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = { ... }
resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-05-01' = { ... }

// Bad
resource StorageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = { ... }
resource virtual_network 'Microsoft.Network/virtualNetworks@2023-05-01' = { ... }
```

### Modules

Use **camelCase** for module names, use descriptive names:

```bicep
// Good
module clusterDeployment 'cluster.bicep' = { ... }
module standaloneDeployment 'standalone.bicep' = { ... }

// Bad
module cluster 'cluster.bicep' = { ... }
module Module1 'standalone.bicep' = { ... }
```

---

## Parameter Guidelines

### Required Parameters

Always document what each parameter does:

```bicep
@description('The name of the storage account (must be globally unique)')
@minLength(3)
@maxLength(24)
param storageAccountName string

@description('Number of Neo4j cluster nodes (1 for standalone, 3-10 for cluster)')
@minValue(1)
@maxValue(10)
param nodeCount int

@description('Azure region for all resources')
param location string = resourceGroup().location
```

### Secure Parameters

Use `@secure()` decorator and **never** provide defaults:

```bicep
// Good
@description('Password for Neo4j admin user')
@secure()
param neo4jPassword string

// Bad - DO NOT DO THIS
@secure()
param neo4jPassword string = 'DefaultPassword123!'
```

### Parameter Validation

Use built-in validation decorators:

```bicep
@description('Neo4j version to deploy')
@allowed([
  '5'
  '4.4'
])
param graphDatabaseVersion string = '5'

@description('VM size for Neo4j nodes')
@allowed([
  'Standard_D4s_v3'
  'Standard_D8s_v3'
  'Standard_D16s_v3'
])
param vmSize string = 'Standard_D4s_v3'

@description('Admin username for VMs')
@minLength(1)
@maxLength(32)
param adminUsername string
```

### Default Values

Provide sensible defaults where appropriate:

```bicep
// Good - safe defaults
param location string = resourceGroup().location
param environment string = 'dev'
param nodeCount int = 1

// Bad - no defaults for required configuration
param location string  // Should have default
param storageAccountName string = 'mystorageaccount'  // Can't have default (must be unique)
```

---

## Security Best Practices

### Never Hardcode Secrets

```bicep
// NEVER do this
param adminPassword string = 'Password123!'
var connectionString = 'Server=...;Password=secret'

// ALWAYS use Key Vault
@secure()
param adminPassword string

// Or retrieve from Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2023-02-01' existing = {
  name: keyVaultName
  scope: resourceGroup(keyVaultResourceGroup)
}
```

### Secure Outputs

```bicep
// Bad - exposing secret in output
@secure()
param adminPassword string

output password string = adminPassword  // Linter will ERROR

// Good - only output non-sensitive information
output vmId string = virtualMachine.id
output publicIP string = publicIPAddress.properties.ipAddress
```

### Managed Identity for Key Vault Access

```bicep
resource virtualMachine 'Microsoft.Compute/virtualMachines@2023-03-01' = {
  name: vmName
  location: location
  identity: {
    type: 'SystemAssigned'  // Enable managed identity
  }
  // ... other properties
}

// Grant Key Vault access to managed identity
resource keyVaultAccessPolicy 'Microsoft.KeyVault/vaults/accessPolicies@2023-02-01' = {
  parent: keyVault
  name: 'add'
  properties: {
    accessPolicies: [
      {
        tenantId: subscription().tenantId
        objectId: virtualMachine.identity.principalId
        permissions: {
          secrets: [
            'get'
            'list'
          ]
        }
      }
    ]
  }
}
```

---

## Resource Configuration

### Location Parameter

Always use location parameter, never hardcode:

```bicep
// Good
param location string = resourceGroup().location

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location  // Use parameter
  // ...
}

// Bad
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: 'eastus'  // Hardcoded - linter will WARN
  // ...
}
```

### API Versions

Use stable, current API versions:

```bicep
// Good - stable, current API version
resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-05-01' = { ... }

// Bad - outdated API version
resource virtualNetwork 'Microsoft.Network/virtualNetworks@2020-05-01' = { ... }

// Bad - preview API version (avoid unless necessary)
resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-06-01-preview' = { ... }
```

### Resource Dependencies

Use symbolic references for dependencies (Bicep handles this automatically):

```bicep
// Good - implicit dependency via reference
resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' = { ... }

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2023-05-01' = {
  parent: vnet  // Implicit dependency
  name: 'default'
  // ...
}

// Also good - reference in properties
resource nic 'Microsoft.Network/networkInterfaces@2023-05-01' = {
  name: nicName
  properties: {
    ipConfigurations: [
      {
        subnet: {
          id: subnet.id  // Implicit dependency via reference
        }
      }
    ]
  }
}

// Bad - explicit dependsOn when not needed
resource nic 'Microsoft.Network/networkInterfaces@2023-05-01' = {
  name: nicName
  dependsOn: [
    subnet  // Unnecessary - already referenced in properties
  ]
  // ...
}
```

### Resource Tagging

Always apply tags to resources:

```bicep
param resourceTags object = {
  Project: 'Neo4j-Enterprise'
  Environment: 'dev'
  ManagedBy: 'Bicep'
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: resourceTags
  // ...
}
```

---

## Code Style

### Formatting

- Use 2 spaces for indentation (not tabs)
- One resource declaration per file section
- Group related parameters, variables, and resources together
- Add blank lines between major sections

### Comments

Use comments to explain **why**, not **what**:

```bicep
// Good - explains the reason
// Using Standard_LRS for cost optimization in dev environment
sku: {
  name: 'Standard_LRS'
}

// Bad - states the obvious
// Set the SKU name to Standard_LRS
sku: {
  name: 'Standard_LRS'
}
```

### String Interpolation

Prefer interpolation over concatenation:

```bicep
// Good
var vmName = '${resourcePrefix}-vm-${uniqueString(resourceGroup().id)}'
var storageUri = 'https://${storageAccount.name}.blob.core.windows.net'

// Bad
var vmName = concat(resourcePrefix, '-vm-', uniqueString(resourceGroup().id))
```

### Conditional Deployments

Use conditions for optional resources:

```bicep
param deployLoadBalancer bool = true

resource loadBalancer 'Microsoft.Network/loadBalancers@2023-05-01' = if (deployLoadBalancer) {
  name: lbName
  // ...
}
```

---

## Documentation

### Template Header

Include a header comment in each template:

```bicep
// Azure Neo4j Enterprise Deployment - Main Template
//
// This template deploys Neo4j Enterprise on Azure with support for:
// - Standalone deployment (1 node)
// - Cluster deployment (3-10 nodes)
// - Optional read replicas
// - Neo4j versions 5.x and 4.4
//
// Version: 2.0
// Last Updated: 2025-11-16

targetScope = 'resourceGroup'

// Parameters
// ...
```

### Parameter Descriptions

Every parameter must have a `@description()`:

```bicep
@description('The name of the Neo4j deployment (used as prefix for resources)')
@minLength(3)
@maxLength(15)
param deploymentName string

@description('Number of Neo4j cluster nodes (1 for standalone, 3-10 for cluster)')
@minValue(1)
@maxValue(10)
param nodeCount int = 1
```

### Output Descriptions

Document all outputs:

```bicep
@description('The resource ID of the deployed virtual machine')
output vmResourceId string = virtualMachine.id

@description('The public IP address of the Neo4j instance')
output publicIPAddress string = publicIP.properties.ipAddress

@description('The connection URL for Neo4j Browser')
output neo4jBrowserUrl string = 'http://${publicIP.properties.ipAddress}:7474'
```

---

## Linter Configuration

### Configured Rules

The repository's `bicepconfig.json` enforces the following rules:

#### Error-Level Rules (Build Failure)

- `adminusername-should-not-be-literal` - Admin usernames must not be hardcoded
- `outputs-should-not-contain-secrets` - Outputs cannot expose secrets
- `protect-commandtoexecute-secrets` - Command execution must not expose secrets
- `secure-parameter-default` - Secure parameters cannot have default values
- `secure-params-in-nested-deploy` - Secure parameters must be properly passed to nested deployments
- `secure-secrets-in-params` - Secrets must use @secure() decorator
- `use-secure-value-for-secure-inputs` - Secure inputs must receive secure values

#### Warning-Level Rules (Non-Blocking)

- `no-hardcoded-env-urls` - Avoid hardcoded environment URLs
- `no-hardcoded-location` - Use location parameter instead of hardcoded locations
- `no-unnecessary-dependson` - Remove unnecessary explicit dependencies
- `no-unused-params` - Remove unused parameters
- `no-unused-vars` - Remove unused variables
- `prefer-interpolation` - Use string interpolation over concatenation
- `simplify-interpolation` - Simplify complex interpolations
- `use-stable-vm-image` - Use stable VM image references

### Running the Linter

Build Bicep files to run linter:

```bash
az bicep build --file mainTemplate.bicep
```

The build will fail if any error-level rules are violated.

### Pre-Commit Hook

Install the pre-commit hook to validate before committing:

```bash
./scripts/install-git-hooks.sh
```

This will automatically run the linter on all staged `.bicep` files before each commit.

---

## Examples

### Compliant Parameter Declaration

```bicep
@description('Storage account name (must be globally unique, 3-24 characters)')
@minLength(3)
@maxLength(24)
param storageAccountName string

@description('Azure region for deployment')
param location string = resourceGroup().location

@description('Environment type')
@allowed([
  'dev'
  'test'
  'prod'
])
param environment string = 'dev'

@description('Neo4j admin password (retrieved from Key Vault)')
@secure()
param neo4jPassword string

@description('Tags to apply to all resources')
param resourceTags object = {
  Environment: environment
  Project: 'Neo4j'
  ManagedBy: 'Bicep'
}
```

### Compliant Resource Declaration

```bicep
resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: '${deploymentName}-vnet'
  location: location
  tags: resourceTags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'default'
        properties: {
          addressPrefix: '10.0.0.0/24'
        }
      }
    ]
  }
}
```

### Compliant Module Usage

```bicep
module clusterDeployment 'cluster.bicep' = if (nodeCount > 1) {
  name: 'neo4j-cluster-deployment'
  params: {
    deploymentName: deploymentName
    location: location
    nodeCount: nodeCount
    vmSize: vmSize
    subnetId: virtualNetwork.properties.subnets[0].id
    resourceTags: resourceTags
  }
}
```

---

## Validation Checklist

Before committing Bicep code, verify:

- [ ] All parameters have `@description()` decorators
- [ ] No hardcoded secrets or passwords
- [ ] All secure parameters use `@secure()` decorator
- [ ] No secure values in outputs
- [ ] Location uses parameter, not hardcoded value
- [ ] All resources have tags applied
- [ ] API versions are stable and current
- [ ] No unused parameters or variables
- [ ] String interpolation used instead of concat()
- [ ] Bicep linter passes with zero errors
- [ ] Code is properly formatted and readable

---

## Getting Help

- See `docs/DEVELOPMENT_SETUP.md` for environment setup
- See [Bicep documentation](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- Review linter error messages and linked documentation
- Check existing templates for examples

---

**Last Updated:** 2025-11-16
