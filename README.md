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
- Python 3.12+ with [uv](https://docs.astral.sh/uv/)
- Git 2.30.0+

**Recommended:**
- Visual Studio Code with Bicep extension

### 2. Verify Your Environment

```bash
./scripts/validate-environment.sh
```

### 3. Deploy and Test Templates

The `deployments/` directory contains a comprehensive CLI for deployment testing:

```bash
cd deployments

# First-time setup
uv run neo4j-deploy setup

# Deploy a scenario
uv run neo4j-deploy deploy --scenario standalone-v5

# Check deployment status
uv run neo4j-deploy status

# Test the deployment
uv run neo4j-deploy test

# Clean up resources
uv run neo4j-deploy cleanup --all --force
```

See **[deployments/README.md](deployments/README.md)** for full command reference.

### 4. Build Marketplace Package

```bash
cd deployments

# Setup: copy .env.sample to .env and add your Partner Center PID
cp ../.env.sample ../.env

# Build enterprise package (creates mainTemplate.json and neo4j-enterprise.zip)
uv run neo4j-deploy package

# Build community package
uv run neo4j-deploy package --template community
```

### 5. Setup GitHub Actions Credentials

Generate Azure Service Principal credentials for GitHub Actions CI/CD:

```bash
cd deployments
uv run setup-azure-credentials
```

This will:
1. Create a Service Principal with Contributor role
2. Save credentials to `azure-credentials.json`
3. Provide instructions for adding to GitHub Secrets

## Manual Deployment

### Enterprise Edition

```bash
cd marketplace/neo4j-enterprise
./deploy.sh <resource-group-name>
```

### Community Edition

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
