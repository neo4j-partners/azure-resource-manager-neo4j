# Azure Neo4j Deployment - Bicep Modernization

This repository contains modernized infrastructure-as-code for deploying Neo4j on Azure, migrating from ARM JSON templates to Azure Bicep.

**📚 [Deployment & Testing Guide](deployments/README.md)** - Automated deployment framework for testing and validating templates

## Overview

This project modernizes the Neo4j Azure deployment infrastructure with:

- **Azure Bicep** - Modern, declarative infrastructure-as-code replacing ARM JSON
- **Cloud-Init** - Declarative VM provisioning replacing complex bash scripts
- **Automated Linting** - Quality and security validation via Bicep linter
- **Simplified Architecture** - Clean, maintainable templates without over-engineering

## Repository Structure

```
├── bicepconfig.json                 # Bicep linter configuration
├── marketplace/
│   ├── neo4j-enterprise/           # Enterprise edition templates
│   ├── neo4j-community/            # Community edition templates
│   └── neo4j-enterprise-aks/       # AKS-based Enterprise templates
├── deployments/                     # Automated testing framework (see deployments/README.md)
│   ├── neo4j_deploy.py             # CLI for deployment testing
│   └── src/                        # Testing modules
├── scripts/
│   ├── neo4j-enterprise/           # Enterprise installation scripts (being modernized)
│   ├── neo4j-community/            # Community installation scripts (being modernized)
│   ├── pre-commit-bicep            # Git pre-commit hook for Bicep validation
│   ├── install-git-hooks.sh        # Hook installation script
│   └── validate-environment.sh     # Development environment validation
```

## Quick Start for Developers

### 1. Install Required Tools

**Required:**
- Azure CLI 2.50.0+
- Bicep CLI 0.20.0+ (bundled with Azure CLI)
- Git 2.30.0+

**Recommended:**
- Visual Studio Code with Bicep extension

### 2. Verify Your Environment

```bash
# Run the validation script
./scripts/validate-environment.sh
```

## Deployment

### Enterprise Edition (Bicep)

The Enterprise edition now uses Bicep templates:

```bash
cd marketplace/neo4j-enterprise
./deploy.sh <resource-group-name>
```

The deployment script will:
1. Create the resource group
2. Compile Bicep to ARM JSON
3. Deploy using Azure CLI
4. Display deployment status and outputs

**For marketplace publishing:**
```bash
cd marketplace/neo4j-enterprise
./makeArchive.sh
```

This generates `archive.zip` containing the compiled ARM template ready for Azure Marketplace.

### Community Edition (Coming Soon)

Community edition Bicep migration is planned for Phase 2.5:

```bash
cd marketplace/neo4j-community
./deploy.sh <resource-group-name>
```

## Azure Marketplace

The templates in this repository are used for:
- [Neo4j Enterprise on Azure Marketplace](https://azuremarketplace.microsoft.com/en-us/marketplace/apps/neo4j.neo4j-ee)
- [Neo4j Community on Azure Marketplace](https://azuremarketplace.microsoft.com/en-us/marketplace/apps/neo4j.neo4j-community)

## Key Features

### Neo4j Enterprise

- Standalone (1 node) or cluster (3-10 nodes) deployments
- Neo4j version 5.x support
- Enterprise and Evaluation license types

### Neo4j Community

- Standalone deployment
- Neo4j version 5.x support
