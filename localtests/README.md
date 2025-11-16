# Neo4j ARM Template Testing Suite

Automated testing framework for Neo4j Enterprise Azure Resource Manager templates.

## Quick Start

```bash
# First-time setup (already completed)
uv run test-arm.py setup

# Validate templates
uv run test-arm.py validate

# Deploy all scenarios
uv run test-arm.py deploy --all

# Deploy specific scenario
uv run test-arm.py deploy --scenario standalone-v5

# Check deployment status
uv run test-arm.py status

# Generate test report
uv run test-arm.py report

# Clean up resources
uv run test-arm.py cleanup --all
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

## Documentation

See SCRIPT_PROPOSAL.md in marketplace/neo4j-enterprise/ for detailed implementation specifications.
