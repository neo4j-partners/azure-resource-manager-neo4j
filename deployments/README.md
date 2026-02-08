# Neo4j Azure Deployment Tools

Automated deployment and testing CLI for Neo4j Enterprise and Community Edition on Azure.

## Quick Start

```bash
# First-time setup
uv run neo4j-deploy setup

# Validate Bicep templates
uv run neo4j-deploy validate

# Deploy a scenario
uv run neo4j-deploy deploy --scenario standalone-lts       # Enterprise LTS
uv run neo4j-deploy deploy --scenario ce-standalone-latest  # Community Edition

# Deploy all scenarios
uv run neo4j-deploy deploy --all

# Check deployment status
uv run neo4j-deploy status

# Test a deployment (connects to Neo4j, runs CRUD validation)
uv run neo4j-deploy test

# Clean up Azure resources
uv run neo4j-deploy cleanup --all
```

## Test Scenarios

Scenarios are defined in `.arm-testing/config/scenarios.yaml`.

### Enterprise

| Scenario | Nodes | Version | License |
|----------|-------|---------|---------|
| `standalone-lts` | 1 | LTS (5) | Evaluation |
| `cluster-lts` | 3 | LTS (5) | Evaluation |

### Community Edition

| Scenario | Nodes | Version | License |
|----------|-------|---------|---------|
| `ce-standalone-latest` | 1 | latest | Community |

The region is set during `uv run neo4j-deploy setup` (Step 3 lets you pick zonal, non-zonal, or quota-restricted). The CE Bicep template uses `pickZones()` to auto-detect availability zone support at deploy time — zonal regions get PremiumV2_LRS + zone pinning, non-zonal regions fall back to Premium_LRS. One scenario works in any region.

## Commands

| Command | Description |
|---------|-------------|
| `setup` | Interactive first-time configuration (region, scenarios, password) |
| `validate` | Validate Bicep templates (lint + compile) |
| `deploy` | Deploy scenarios (`--scenario NAME` or `--all`) |
| `test` | Validate deployed Neo4j (connectivity, CRUD, license) |
| `status` | Show deployment status |
| `cleanup` | Delete Azure resource groups (`--all` or `--scenario NAME`) |
| `ee-package` | Build Enterprise marketplace archive for Partner Center |
| `ce-package` | Build Community Edition marketplace archive for Partner Center |

### Deploy options

```bash
uv run neo4j-deploy deploy --scenario <name>     # Single scenario
uv run neo4j-deploy deploy --all                  # All scenarios
uv run neo4j-deploy deploy --scenario <name> --dry-run  # Preview only
```

The deploy region is always the default set during `uv run neo4j-deploy setup`. Re-run setup to change it.

## Configuration

Configuration files are in `.arm-testing/config/`:

| File | Purpose |
|------|---------|
| `settings.yaml` | Azure subscription, default region, cleanup mode, password strategy |
| `scenarios.yaml` | Test scenario definitions (name, VM size, version, license, disk) |

The `.arm-testing/` directory also contains:
- `state/` - Active deployment tracking
- `params/` - Generated ARM parameter files
- `results/` - Connection info and test results

## Requirements

- Python 3.12+ with [uv](https://docs.astral.sh/uv/)
- Azure CLI (`az`) installed and logged in
- Active Azure subscription with Contributor role
