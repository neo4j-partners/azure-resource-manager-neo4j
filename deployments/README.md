# Neo4j Azure Deployment Tools

Automated deployment and testing framework for Neo4j on Azure, supporting both Enterprise and Community Edition.

## Quick Start

```bash
# First-time setup
uv run neo4j-deploy setup

# Validate templates
uv run neo4j-deploy validate

# Deploy all scenarios (Enterprise and Community)
uv run neo4j-deploy deploy --all

# Deploy specific scenario
uv run neo4j-deploy deploy --scenario standalone-v5       # Enterprise
uv run neo4j-deploy deploy --scenario ce-standalone-v5    # Community Edition

# Check deployment status
uv run neo4j-deploy status

# Test a deployment
uv run neo4j-deploy test

# Clean up resources
uv run neo4j-deploy cleanup --all
```

## Supported Editions

| Edition | Template | Scenarios | Clustering |
|---------|----------|-----------|------------|
| Enterprise | `marketplace/neo4j-enterprise/` | standalone, cluster (3-10 nodes) | Yes |
| Community | `marketplace/neo4j-ce/` | standalone only | No |

The framework automatically selects the correct template based on the scenario's `license_type` field:
- `license_type: "Enterprise"` or `"Evaluation"` → uses `neo4j-enterprise` template
- `license_type: "Community"` → uses `neo4j-ce` template

## Default Scenarios

After running `setup`, the following default scenarios are created:

| Scenario | Edition | Nodes | Version |
|----------|---------|-------|---------|
| `standalone-v5` | Evaluation | 1 | 5 (LTS) |
| `cluster-v5` | Evaluation | 3 | 5 (LTS) |
| `ce-standalone-v5` | Community | 1 | 5 (LTS) |
| `ce-standalone-latest` | Community | 1 | latest (CalVer) |

Edit `.arm-testing/config/scenarios.yaml` to customize.

## Packaging for Marketplace

```bash
# Package Enterprise template
uv run neo4j-deploy package

# Package Community Edition template
uv run neo4j-deploy package --edition community
```

## Configuration

Configuration files are located in `.arm-testing/config/`:
- `settings.yaml` - Main settings (Azure subscription, regions, cleanup modes)
- `scenarios.yaml` - Test scenario definitions

Example templates are in `.arm-testing/templates/`

## Directory Structure

```
.arm-testing/
├── config/       # Configuration files
├── state/        # Deployment tracking
├── params/       # Generated parameter files
├── results/      # Test outputs and reports
├── logs/         # Execution logs
├── cache/        # Downloaded binaries
└── templates/    # Example configurations
```

## Requirements

- Python 3.12+ with uv
- Azure CLI (`az`) installed and configured
- Git (for automatic branch detection)
- Active Azure subscription
