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

### ARM Template Structure

Each marketplace template includes:
- **mainTemplate.json** - The primary ARM template defining all Azure resources (VMs, networks, load balancers, etc.)
- **createUiDefinition.json** - Defines the Azure Portal UI for template deployment
- **parameters.json** - Default/test parameters for template deployment

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

### Template Artifact Location

ARM templates reference scripts via the `_artifactsLocation` parameter. This points to raw GitHub URLs and must be updated when testing branches other than main. The parameter is automatically set during marketplace deployment but must be manually configured for local testing.

## Testing ARM Templates

### Running Tests via GitHub Actions

Two workflow files exist that test template deployments:
- `.github/workflows/enterprise.yml` - Tests Enterprise templates with multiple configurations
- `.github/workflows/community.yml` - Tests Community templates

Both workflows can be triggered via:
- Pull requests affecting template files
- Manual dispatch using `workflow_dispatch` event

The workflows:
1. Create temporary Azure resource groups
2. Deploy ARM templates with test parameters
3. Run neo4jtester to validate the deployment
4. Clean up resources (always runs, even on failure)

### Local Template Testing

To test templates locally:

1. Update `_artifactsLocation` in `parameters.json` to point to your branch:
   ```json
   "_artifactsLocation": {
     "value": "https://raw.githubusercontent.com/neo4j-partners/azure-resource-manager-neo4j/<branch-name>/"
   }
   ```

2. Deploy using the provided script:
   ```bash
   cd marketplace/neo4j-enterprise  # or neo4j-community
   ./deploy.sh <resource-group-name>
   ```

3. Clean up after testing:
   ```bash
   ./delete.sh <resource-group-name>
   ```

### Template Deployment Parameters

Enterprise templates accept these key parameters via CLI override:
- `nodeCount` - Number of cluster nodes (1, 3-10)
- `graphDatabaseVersion` - "5" or "4.4"
- `licenseType` - "Enterprise" or "Evaluation"
- `readReplicaCount` - Number of read replicas (0-10)
- `_artifactsLocation` - Base URL for script artifacts

Example from workflow:
```bash
az deployment group create \
  --template-file ./marketplace/neo4j-enterprise/mainTemplate.json \
  --parameters ./marketplace/neo4j-enterprise/parameters.json \
  nodeCount="3" \
  graphDatabaseVersion="5" \
  _artifactsLocation="https://raw.githubusercontent.com/org/repo/branch/"
```

## Publishing to Azure Marketplace

To update marketplace listings (Neo4j employees only):

1. Run the archive script:
   ```bash
   cd marketplace/neo4j-enterprise  # or neo4j-community
   ./makeArchive.sh
   ```

2. Upload the resulting `archive.zip` to [Azure Partner Portal](https://partner.microsoft.com/en-us/dashboard/commercial-marketplace/overview)

## Azure CLI Requirements

Working with this repository requires Azure CLI (`az`) for:
- Testing template deployments
- Managing resource groups
- Building VM images
- Generating SAS URIs for marketplace VM images

## Template Validation

Test outputs are validated using [neo4jtester](https://github.com/neo4j/neo4jtester), which connects to the deployed Neo4j instance and verifies:
- Database connectivity via Neo4j protocol
- Correct edition (Community, Enterprise, or Evaluation)
- Basic database operations
