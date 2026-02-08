# Azure Neo4j Deployment

Infrastructure-as-code for deploying Neo4j on Azure using Bicep templates, published to the Azure Marketplace.

## Editions

| Edition | Template | VM | Disk | Nodes |
|---------|----------|-----|------|-------|
| **Enterprise** | `marketplace/neo4j-enterprise/` | VMSS (Standard_E4s_v5) | Premium_LRS | 1-10 |
| **Community** | `marketplace/neo4j-ce/` | Standalone VM (Standard_E4bds_v5, NVMe) | PremiumV2_LRS / Premium_LRS (auto) | 1 |

The CE template uses `pickZones()` to auto-detect availability zone support at deploy time. In zonal regions it deploys with PremiumV2_LRS + zone 1; in non-zonal regions it falls back to Premium_LRS with no zone pinning. See [CE Architecture](marketplace/neo4j-ce/ARCHITECTURE.md) for details.

## Repository Structure

```
marketplace/
  neo4j-enterprise/         # Enterprise edition (VMSS, load balancer)
  neo4j-ce/                 # Community Edition (standalone VM, NVMe, pickZones)
scripts/
  neo4j-enterprise/         # Enterprise cloud-init and provisioning
  neo4j-ce/cloud-init/      # CE cloud-init (standalone.yaml)
deployments/                # Deployment and testing CLI (see deployments/README.md)
.github/workflows/          # CI: enterprise.yml, community.yml
```

## Quick Start

### Deploy and Test

```bash
cd deployments

# First-time setup
uv run neo4j-deploy setup

# Deploy Enterprise standalone
uv run neo4j-deploy deploy --scenario standalone-lts

# Deploy Community Edition
uv run neo4j-deploy deploy --scenario ce-standalone-latest

# Deploy CE to a non-zonal region (tests pickZones fallback)
uv run neo4j-deploy deploy --scenario ce-standalone-nonzonal --region northcentralus

# Check status, test, clean up
uv run neo4j-deploy status
uv run neo4j-deploy test
uv run neo4j-deploy cleanup --all --force
```

See **[deployments/README.md](deployments/README.md)** for full command reference.

### Build Marketplace Package

```bash
cd deployments
uv run neo4j-deploy package
```

### Manual Deployment

```bash
# Enterprise
cd marketplace/neo4j-enterprise && ./deploy.sh <resource-group-name>

# Community Edition
cd marketplace/neo4j-ce && ./deploy.sh <resource-group-name>
```

## Requirements

- Azure CLI 2.50.0+ (includes Bicep CLI)
- Python 3.12+ with [uv](https://docs.astral.sh/uv/)
- Active Azure subscription

## Test Scenarios

| Scenario | Edition | Version | Purpose |
|----------|---------|---------|---------|
| `standalone-lts` | Enterprise Evaluation | LTS (5) | Single-node enterprise |
| `cluster-lts` | Enterprise Evaluation | LTS (5) | 3-node cluster |
| `ce-standalone-latest` | Community | CalVer (latest) | CE in zonal region (default eastus2) |
| `ce-standalone-nonzonal` | Community | CalVer (latest) | CE in non-zonal region (northcentralus) |
| `ce-standalone-restricted` | Community | CalVer (latest) | CE in quota-restricted region (westeurope) |

## CI/CD

GitHub Actions workflows validate deployments on pull requests:
- `enterprise.yml` - Enterprise standalone + cluster (LTS, Enterprise and Evaluation licenses)
- `community.yml` - Community Edition standalone

## Azure Marketplace

- [Neo4j Enterprise on Azure Marketplace](https://azuremarketplace.microsoft.com/en-us/marketplace/apps/neo4j.neo4j-ee)
