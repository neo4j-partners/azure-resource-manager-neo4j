# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This repository contains Azure infrastructure-as-code for deploying Neo4j on Azure. It supports three deployment models:

1. **VM-based Enterprise** - VMSS clusters with load balancers
2. **VM-based Community** - Single VM standalone deployment
3. **AKS-based Enterprise** - Kubernetes deployment using Helm charts

All templates use Azure Bicep (modern infrastructure-as-code) compiled to ARM JSON for marketplace publishing.

## Repository Structure

```
├── marketplace/
│   ├── neo4j-enterprise/           # VM-based Enterprise (VMSS)
│   ├── neo4j-community/            # VM-based Community (single VM)
│   └── neo4j-enterprise-aks/       # AKS-based Enterprise (Helm)
├── scripts/
│   ├── neo4j-enterprise/           # VM provisioning scripts
│   └── neo4j-community/            # Community VM scripts
├── deployments/                     # Python testing framework
│   ├── neo4j_deploy.py             # CLI entry point
│   └── src/                        # Testing modules
├── docs/                           # Architecture and standards docs
└── bicepconfig.json                # Bicep linter configuration
```

## Architecture: Three Deployment Models

### 1. VM-based Enterprise (`marketplace/neo4j-enterprise/`)

Modular Bicep template deploying Neo4j on Azure VM Scale Sets:

**Key modules:**
- `modules/network.bicep` - VNet, subnets, NSG
- `modules/identity.bicep` - Managed identity
- `modules/loadbalancer.bicep` - Azure Load Balancer
- `modules/vmss.bicep` - Primary cluster nodes
- `modules/vmss-read-replica.bicep` - Optional read replicas

**Deployment options:**
- Standalone (1 node) or cluster (3-10 nodes)
- Neo4j 5.x or 4.4
- Read replicas (0-10)
- Plugins: Graph Data Science, Bloom
- License: Enterprise or Evaluation

### 2. VM-based Community (`marketplace/neo4j-community/`)

Simpler Bicep template for standalone Community edition:

**Key modules:**
- `modules/network.bicep` - VNet and NSG
- `modules/identity.bicep` - Managed identity
- `modules/vm.bicep` - Single VM deployment

**Deployment options:**
- Standalone only (1 node)
- Neo4j 5.x Community

### 3. AKS-based Enterprise (`marketplace/neo4j-enterprise-aks/`)

Modern Kubernetes deployment using official Neo4j Helm chart:

**Key modules:**
- `modules/network.bicep` - VNet for AKS
- `modules/identity.bicep` - Workload identity
- `modules/aks-cluster.bicep` - Managed Kubernetes cluster
- `modules/storage.bicep` - Premium SSD storage class
- `modules/helm-deployment.bicep` - Neo4j Helm chart deployment

**Deployment approach:**
- Infrastructure provisioning (Bicep) → Application deployment (Helm)
- Helm chart deployed via Azure Deployment Script resource
- StatefulSets with persistent volumes
- LoadBalancer service for external access

**Deployment options:**
- Standalone (1 pod) or cluster (3-10 pods)
- Neo4j 5.x Enterprise
- Kubernetes 1.30+

## Common Commands

### Deploying Templates Locally

**Enterprise VM-based:**
```bash
cd marketplace/neo4j-enterprise
./deploy.sh <resource-group-name>
```

**Community VM-based:**
```bash
cd marketplace/neo4j-community
./deploy.sh <resource-group-name>
```

**Enterprise AKS-based:**
```bash
cd marketplace/neo4j-enterprise-aks
./deploy.sh <resource-group-name>
```

All deploy scripts:
1. Create resource group
2. Compile `main.bicep` to `mainTemplate-generated.json`
3. Deploy using `az deployment group create`
4. Clean up temporary JSON file

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

**Enterprise VM-based:**
```bash
cd marketplace/neo4j-enterprise
./makeArchive.sh
```

**Community VM-based:**
```bash
cd marketplace/neo4j-community
./makeArchive.sh
```

Both scripts:
1. Compile `main.bicep` → `mainTemplate.json`
2. Package into `archive.zip` for marketplace
3. Clean up temporary files

Upload `archive.zip` to [Azure Partner Portal](https://partner.microsoft.com/en-us/dashboard/commercial-marketplace/overview)

**Note:** AKS deployment is currently in development and not yet published to marketplace.

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
- `scripts/neo4j-enterprise/node4.sh` - Neo4j 4.4
- `scripts/neo4j-enterprise/readreplica4.sh` - Read replica setup

**Community scripts:**
- `scripts/neo4j-community/node.sh` - Neo4j 5.x Community

**Future migration:** Scripts will be replaced with cloud-init YAML embedded in Bicep using `loadTextContent()`.

### Helm Chart Deployment in AKS

The AKS deployment uses Azure Deployment Script resource to run Helm commands:

1. Bicep provisions AKS cluster and supporting infrastructure
2. Deployment Script resource (container instance) runs Helm install
3. Helm chart creates StatefulSets, Services, ConfigMaps, Secrets
4. LoadBalancer service exposes Neo4j to external traffic

Key configuration:
- Storage class: Premium SSD with retain policy
- Service type: LoadBalancer (gets Azure public IP)
- Helm chart: `neo4j/neo4j` from Neo4j Helm repository
- Values passed from Bicep parameters to Helm

**Critical:** The `modules/helm-deployment.bicep` module orchestrates this process. The Deployment Script requires:
- Managed identity with AKS contributor role
- kubectl access to cluster
- Helm 3.x installed in container

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

Two workflows test deployments:

**`.github/workflows/enterprise.yml`** - Enterprise VM-based
- Tests standalone, 3-node cluster, 5-node cluster scenarios
- Neo4j 5.x and 4.4 versions
- Runs on pull requests affecting enterprise templates

**`.github/workflows/community.yml`** - Community VM-based
- Tests standalone scenario
- Neo4j 5.x Community
- Runs on pull requests affecting community templates

Both workflows:
1. Compile Bicep to ARM JSON
2. Deploy to temporary resource group
3. Run `uv run validate_deploy` to verify deployment
4. Clean up resources

## Development Standards

Read `docs/BICEP_STANDARDS.md` for comprehensive standards. Key points:

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

All templates accept parameter overrides via CLI:

**Common parameters:**
- `nodeCount` - Cluster size (1, 3-10)
- `graphDatabaseVersion` - "5" or "4.4"
- `adminPassword` - Neo4j password (secure string)
- `licenseType` - "Enterprise" or "Evaluation"
- `vmSize` / `userNodeSize` - Azure VM size
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

- `docs/DEVELOPMENT_SETUP.md` - Environment setup, prerequisites
- `docs/BICEP_STANDARDS.md` - Coding standards and conventions
- `docs/ENTERPRISE_KEY_VAULT_GUIDE.md` - Key Vault integration patterns
- `marketplace/neo4j-enterprise-aks/README.md` - AKS deployment guide
- `deployments/README.md` - Testing framework usage
