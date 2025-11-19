# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This repository contains Azure Resource Manager (ARM) templates for deploying Neo4j on Azure. It supports both Neo4j Enterprise and Community editions with deployment configurations for standalone instances, clusters, and read replicas.

## Repository Structure

The repository is organized into two main directories:

- **marketplace/** - Contains ARM templates used in the Azure Marketplace listings for both Enterprise and Community editions. These are the primary deployment templates.
- **scripts/** - Contains shell scripts that are executed during VM provisioning via ARM template extensions.

Each edition has its own subdirectory:
- `marketplace/neo4j-enterprise/` - Enterprise edition marketplace template
- `marketplace/neo4j-community/` - Community edition marketplace template
- `scripts/neo4j-enterprise/` - Enterprise installation scripts
- `scripts/neo4j-community/` - Community installation scripts

## Key Architecture Points

### Bicep Template Structure (Enterprise Edition)

**Enterprise edition** now uses modular Azure Bicep templates:
- **main.bicep** - The primary Bicep template orchestrating all modules
- **modules/** - Directory containing modular Bicep files (network, identity, loadbalancer, vmss, vmss-read-replica)
- **createUiDefinition.json** - Defines the Azure Portal UI for template deployment
- **parameters.json** - Default/test parameters for template deployment
- **mainTemplate.json** - Generated from Bicep during archive creation for marketplace publishing

**Community edition** still uses ARM JSON templates (migration planned for Phase 2.5):
- **mainTemplate.json** - ARM template for Community edition
- **createUiDefinition.json** - Azure Portal UI definition
- **parameters.json** - Default/test parameters

### Deployment Configurations

The templates support multiple deployment modes:

**Enterprise Edition:**
- Standalone (nodeCount=1) or Cluster (nodeCount=3-10)
- Neo4j versions 5.x or 4.4
- Optional read replicas (readReplicaCount=0-10)
- Optional Graph Data Science and Bloom plugins
- License types: "Enterprise" or "Evaluation"

**Community Edition:**
- Standalone deployment only
- Neo4j version 5.x

### Installation Scripts

The `scripts/` directory contains bash scripts that run on the VMs:

**Enterprise scripts:**
- `node.sh` - Neo4j 5.x installation and configuration
- `node4.sh` - Neo4j 4.4 installation and configuration
- `readreplica4.sh` - Read replica setup for 4.4

**Community scripts:**
- `node.sh` - Neo4j 5.x Community installation

These scripts handle disk mounting, Neo4j installation, cluster configuration, plugin installation, and Azure integration.

### Script URLs in Bicep Templates

**Enterprise Edition (Bicep):**
Scripts are referenced via the `scriptsBaseUrl` variable that points to GitHub raw URLs:
```bicep
var scriptsBaseUrl = 'https://raw.githubusercontent.com/neo4j-partners/azure-resource-manager-neo4j/main/'
```

This replaces the previous `_artifactsLocation` parameter pattern. Scripts are downloaded during VM provisioning via CustomScript extension.

**Future (Phase 3):** Scripts will be replaced with cloud-init YAML embedded directly in Bicep templates using `loadTextContent()` function.

## Testing Templates

### Running Tests via GitHub Actions

Two workflow files exist that test template deployments:
- `.github/workflows/enterprise.yml` - Tests Enterprise Bicep templates with multiple configurations
- `.github/workflows/community.yml` - Tests Community ARM templates

Both workflows can be triggered via:
- Pull requests affecting template files
- Manual dispatch using `workflow_dispatch` event

The workflows:
1. Create temporary Azure resource groups
2. Deploy templates with test parameters (Bicep for Enterprise, ARM JSON for Community)
3. Run `validate_deploy` to validate the deployment

**Note:** Enterprise workflow will be updated to use Bicep in upcoming commits.

### Local Template Testing

**Enterprise Edition (Bicep):**
```bash
cd marketplace/neo4j-enterprise
./deploy.sh <resource-group-name>
```

The deploy script automatically:
1. Creates the resource group
2. Compiles Bicep to ARM JSON
3. Deploys using Azure CLI
4. Displays deployment status

**Community Edition (ARM JSON):**
```bash
cd marketplace/neo4j-community
./deploy.sh <resource-group-name>
```

**Validation:**
After deployment, validate using:
```bash
cd deployments
uv run validate_deploy <scenario-name>
```

Where `<scenario-name>` matches your deployment (e.g., `standalone-v5`, `cluster-3node-v5`)

**Cleanup:**
```bash
./delete.sh <resource-group-name>
```

### Template Deployment Parameters

Enterprise Bicep templates accept these key parameters via CLI override:
- `nodeCount` - Number of cluster nodes (1, 3-10)
- `graphDatabaseVersion` - "5" or "4.4"
- `licenseType` - "Enterprise" or "Evaluation"
- `readReplicaCount` - Number of read replicas (0-10)
- `vmSize` - Azure VM size for cluster nodes
- `diskSize` - Data disk size in GB

Example deployment:
```bash
az deployment group create \
  --template-file ./marketplace/neo4j-enterprise/main.bicep \
  --parameters ./marketplace/neo4j-enterprise/parameters.json \
  nodeCount="3" \
  graphDatabaseVersion="5" \
  licenseType="Evaluation"
```

**Note:** Script URLs are hardcoded in the Bicep template (`scriptsBaseUrl` variable) and will be replaced with cloud-init in Phase 3.

## Publishing to Azure Marketplace

To update marketplace listings (Neo4j employees only):

**Enterprise Edition (Bicep):**
```bash
cd marketplace/neo4j-enterprise
./makeArchive.sh
```

The script automatically:
1. Compiles `main.bicep` to `mainTemplate.json`
2. Packages ARM template, scripts, and UI definition into `archive.zip`
3. Cleans up temporary files

**Community Edition (ARM JSON):**
```bash
cd marketplace/neo4j-community
./makeArchive.sh
```

**Upload:**
Upload the resulting `archive.zip` to [Azure Partner Portal](https://partner.microsoft.com/en-us/dashboard/commercial-marketplace/overview)

## Azure CLI and Bicep Requirements

Working with this repository requires:

**Azure CLI** (`az`) for:
- Testing template deployments
- Managing resource groups
- Building VM images
- Generating SAS URIs for marketplace VM images

**Bicep CLI** (bundled with Azure CLI 2.20.0+) for:
- Compiling Bicep templates to ARM JSON
- Template validation and linting
- Local development and testing

Verify Bicep is installed:
```bash
az bicep version
```

See [docs/DEVELOPMENT_SETUP.md](docs/DEVELOPMENT_SETUP.md) for full setup instructions.

## Template Validation

Deployments are validated using `validate_deploy` (in `deployments/`), which:
- Connects to the deployed Neo4j instance via Bolt protocol
- Creates and verifies a test dataset (Movies graph)
- Checks license type (Evaluation vs Enterprise)
- Validates basic database operations
- Cleans up test data

Usage:
```bash
cd deployments
uv run validate_deploy <scenario-name>
```
