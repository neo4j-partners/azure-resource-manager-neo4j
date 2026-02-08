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
test_suite/test_ce/         # CE integration tests (connectivity, CRUD, resilience)
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

# Deploy Community Edition (region set during setup)
uv run neo4j-deploy deploy --scenario ce-standalone-latest

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
| `ce-standalone-latest` | Community | CalVer (latest) | CE standalone (region set during setup, `pickZones` auto-adapts) |

## CE Integration Tests

The `test_suite/test_ce/` package runs integration tests against a deployed Community Edition instance.

**What it tests:**
- HTTP API and authenticated HTTP connectivity
- Bolt protocol connectivity
- APOC plugin availability
- Community Edition verification (`dbms.components()`)
- CRUD validation using a Movies graph dataset (The Matrix trilogy, 11+ nodes)
- VM provisioning and data disk attachment (full mode, via Azure SDK)
- Data persistence through a VM restart cycle (full mode)

**Running the tests:**

```bash
cd test_suite/test_ce

# Use the latest connection file (default)
uv run test-ce

# Use a specific connection file
uv run test-ce --results connection-ce-standalone-latest-20260207-212235.json

# Simple mode — connectivity + CRUD only, skips Azure resource checks
uv run test-ce --simple
```

Connection details and password are read from `deployments/.arm-testing/results/`. When `--results` is omitted the most recent connection file is used.

## CI/CD

GitHub Actions workflows validate deployments on pull requests:
- `enterprise.yml` - Enterprise standalone + cluster (LTS, Enterprise and Evaluation licenses)
- `community.yml` - Community Edition standalone

## Azure Marketplace

- [Neo4j Enterprise on Azure Marketplace](https://azuremarketplace.microsoft.com/en-us/marketplace/apps/neo4j.neo4j-ee)
