# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This repository contains Azure infrastructure-as-code for deploying Neo4j Enterprise on Azure using VM Scale Sets (VMSS) with load balancers.

All templates use Azure Bicep (modern infrastructure-as-code) compiled to ARM JSON for marketplace publishing.

## Repository Structure

```
├── marketplace/
│   └── neo4j-enterprise/           # VM-based Enterprise (VMSS)
├── scripts/
│   └── neo4j-enterprise/           # VM provisioning scripts
├── deployments/                     # Python testing framework
│   ├── neo4j_deploy.py             # CLI entry point
│   └── src/                        # Testing modules
└── bicepconfig.json                # Bicep linter configuration
```

## Architecture: VM-based Enterprise (`marketplace/neo4j-enterprise/`)

Modular Bicep template deploying Neo4j on Azure VM Scale Sets:

**Key modules:**
- `modules/network.bicep` - VNet, subnets, NSG
- `modules/identity.bicep` - Managed identity
- `modules/loadbalancer.bicep` - Azure Load Balancer
- `modules/vmss.bicep` - Primary cluster nodes

**Deployment options:**
- Standalone (1 node) or cluster (3-10 nodes)
- Neo4j 5.x
- License: Enterprise or Evaluation

## Common Commands

### Deploying Templates Locally

```bash
cd marketplace/neo4j-enterprise
./deploy.sh <resource-group-name>
```

The deploy script:
1. Creates resource group
2. Compiles `main.bicep` to `mainTemplate-generated.json`
3. Deploys using `az deployment group create`
4. Cleans up temporary JSON file

### Validating Deployments

The `deployments/` directory contains a Python-based testing framework:

```bash
# First-time setup
cd deployments
uv run neo4j-deploy setup

# Validate templates (Bicep linting)
uv run neo4j-deploy validate

# Deploy and test specific scenario
uv run neo4j-deploy deploy --scenario standalone-v5

# Check deployment status
uv run neo4j-deploy status

# Clean up resources
uv run neo4j-deploy cleanup --all
```

### Validating Individual Deployments

After manual deployment, validate using:
```bash
cd deployments
uv run validate_deploy <scenario-name>
```

This connects to Neo4j via Bolt protocol and validates:
- Database connectivity
- License type
- CRUD operations (creates Movies graph dataset)
- Cleanup of test data

### Publishing to Azure Marketplace

```bash
cd marketplace/neo4j-enterprise
./makeArchive.sh
```

This script:
1. Compiles `main.bicep` → `mainTemplate.json`
2. Packages into `archive.zip` for marketplace
3. Cleans up temporary files

Upload `archive.zip` to [Azure Partner Portal](https://partner.microsoft.com/en-us/dashboard/commercial-marketplace/overview)

### Bicep Development

**Compile Bicep to ARM JSON:**
```bash
az bicep build --file main.bicep --outfile mainTemplate.json
```

**Validate Bicep:**
```bash
az bicep build --file main.bicep
```

Bicep linter runs automatically during build. Configuration in `bicepconfig.json` enforces:
- No hardcoded secrets
- Secure parameters for sensitive data
- No secret exposure in outputs
- Stable resource identifiers

**Pre-commit hook:**
```bash
./scripts/install-git-hooks.sh
```

This installs a hook that validates Bicep files before commits.

## Critical Architectural Details

### Script Execution in VM-based Deployments

VM provisioning uses CustomScript extension that downloads and executes bash scripts from GitHub:

```bicep
var scriptsBaseUrl = 'https://raw.githubusercontent.com/neo4j-partners/azure-resource-manager-neo4j/main/'
```

Scripts handle:
- Data disk mounting and formatting
- Neo4j installation from Debian packages
- Cluster configuration (discovery via Azure metadata)
- Plugin installation (GDS, Bloom)
- Service startup

**Enterprise scripts:**
- `scripts/neo4j-enterprise/node.sh` - Neo4j 5.x

**Future migration:** Scripts will be replaced with cloud-init YAML embedded in Bicep using `loadTextContent()`.

## Testing Framework Architecture

The `deployments/` directory contains a comprehensive Python testing framework built with:
- **Typer** - CLI interface
- **Rich** - Terminal output formatting
- **neo4j** - Bolt protocol client
- **Azure SDK** - Resource group management

**Key components:**
- `neo4j_deploy.py` - Main CLI entry point
- `src/orchestrator.py` - Deployment orchestration
- `src/validate_deploy.py` - Neo4j connectivity validation
- `src/deployment.py` - Azure deployment operations
- `src/config.py` - Configuration management

Configuration stored in `.arm-testing/`:
- `config/settings.yaml` - Azure subscription, regions
- `config/scenarios.yaml` - Test scenario definitions
- `state/` - Deployment tracking
- `results/` - Test outputs and reports

## GitHub Actions CI/CD

**`.github/workflows/enterprise.yml`** - Enterprise VM-based
- Tests standalone, 3-node cluster, 5-node cluster scenarios
- Neo4j 5.x
- Runs on pull requests affecting enterprise templates

The workflow:
1. Compiles Bicep to ARM JSON
2. Deploys to temporary resource group
3. Runs `uv run validate_deploy` to verify deployment
4. Cleans up resources

## Development Standards

**Bicep conventions:**
- Use modules for clear separation (network, compute, storage)
- Parameter descriptions required for all parameters
- Use `@secure()` decorator for passwords and secrets
- Resource naming: `${prefix}-${resourceType}-${suffix}`
- Tag all resources with deployment metadata

**Security requirements:**
- Never hardcode secrets in templates
- Use Azure Key Vault with managed identity (where applicable)
- Validate outputs don't expose secrets
- Follow principle of least privilege for managed identities

**Code style:**
- Prefer clarity over cleverness
- No unnecessary abstraction
- Complete cut-over (no compatibility layers)
- Document complex logic with comments

## Parameter Overrides

Templates accept parameter overrides via CLI:

**Common parameters:**
- `nodeCount` - Cluster size (1, 3-10)
- `graphDatabaseVersion` - "5"
- `adminPassword` - Neo4j password (secure string)
- `licenseType` - "Enterprise" or "Evaluation"
- `vmSize` - Azure VM size
- `diskSize` - Data disk size in GB

**Example:**
```bash
az deployment group create \
  --resource-group my-rg \
  --template-file main.bicep \
  --parameters @parameters.json \
  --parameters nodeCount=3 adminPassword="SecurePass123!" licenseType="Enterprise"
```

## Useful Documentation

- `deployments/README.md` - Testing framework usage
