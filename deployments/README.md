# Neo4j Azure Deployment Tools

Automated deployment and testing framework for Neo4j Enterprise on Azure.

## Quick Start

```bash
# First-time setup (already completed)
uv run neo4j-deploy setup

# Validate templates
uv run neo4j-deploy validate

# Deploy all scenarios
uv run neo4j-deploy deploy --all

# Deploy specific scenario
uv run neo4j-deploy deploy --scenario standalone-v5

# Check deployment status
uv run neo4j-deploy status

# Generate test report
uv run neo4j-deploy report

# Clean up resources
uv run neo4j-deploy cleanup --all
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

