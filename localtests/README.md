# Neo4j ARM Template Testing Suite

Automated testing framework for Neo4j Enterprise Azure Resource Manager templates.

## Current Status: 50% Complete (Phase 5 Done! 🎉)

**What's Working:**
- ✅ Interactive setup wizard
- ✅ Configuration management
- ✅ Parameter file generation
- ✅ Template validation and what-if analysis
- ✅ Cost estimation
- ✅ **Full deployment execution to Azure**
- ✅ **Live deployment monitoring**
- ✅ **Connection info extraction and storage**

**What's Next:**
- ⏳ Post-deployment testing with neo4jtester (Phase 6)
- ⏳ Automated cleanup (Phase 7)
- ⏳ Reporting and logging (Phase 8)

## Quick Start

```bash
# First-time setup
uv run test-arm.py setup

# Validate templates (dry-run check)
uv run test-arm.py validate

# Preview deployment without executing
uv run test-arm.py deploy --scenario standalone-v5 --dry-run

# Deploy and monitor in real-time
uv run test-arm.py deploy --scenario standalone-v5

# Deploy all scenarios in parallel
uv run test-arm.py deploy --all

# Deploy with custom settings
uv run test-arm.py deploy --scenario cluster-v5 --region eastus2 --parallel 3

# Check deployment status (not yet implemented)
uv run test-arm.py status

# Test a deployment (not yet implemented)
uv run test-arm.py test <deployment-id>

# Clean up resources (not yet implemented)
uv run test-arm.py cleanup --all
```

## Testing the Current Implementation

### Phase 5 Testing (Deployment Execution)

To test the current implementation without incurring significant Azure costs:

#### 1. Validate Configuration
```bash
# Ensure setup is complete
uv run test-arm.py setup --force

# Validate templates (no deployment)
uv run test-arm.py validate --scenario standalone-v5
```

#### 2. Test Parameter Generation
```bash
# Generate parameters without deploying
uv run test-arm.py deploy --scenario standalone-v5 --dry-run

# Check generated files
ls -lh .arm-testing/params/
cat .arm-testing/params/params-standalone-v5-*.json
```

#### 3. Test Single Deployment (Actual Azure Deployment)
```bash
# Deploy single standalone instance
uv run test-arm.py deploy --scenario standalone-v5

# What to expect:
# - Resource group creation with timestamped name
# - Deployment submission to Azure
# - Live monitoring dashboard (updates every 30 seconds)
# - Connection info extraction on success
# - Deployment takes ~5-10 minutes for standalone instances
```

#### 4. Monitor Deployment Progress
While deployment is running, you'll see:
- Live table showing scenario, resource group, status, and duration
- Color-coded status: yellow (Running), green (Succeeded), red (Failed)
- Automatic updates every 30 seconds
- Error details if deployment fails

#### 5. Check Generated Files
After successful deployment:
```bash
# View saved connection information
ls -lh .arm-testing/results/
cat .arm-testing/results/connection-standalone-v5-*.json

# Check deployment state tracking
cat .arm-testing/state/active-deployments.json
```

#### 6. Manual Cleanup (Until Phase 7 is Complete)
```bash
# List managed resource groups
az group list --tag managed-by=test-arm-script --output table

# Delete specific resource group
az group delete --name <resource-group-name> --yes --no-wait
```

### Expected Output Files

After a successful deployment:
```
.arm-testing/
├── params/
│   └── params-standalone-v5-20250116-143052.json    # Generated parameters
├── results/
│   └── connection-standalone-v5-20250116-143052.json # Connection info
└── state/
    └── active-deployments.json                       # Deployment tracking
```

### Connection Info Format

The connection info JSON includes:
```json
{
  "deployment_id": "uuid",
  "scenario_name": "standalone-v5",
  "resource_group": "neo4j-test-standalone-v5-20250116-143052",
  "neo4j_uri": "neo4j://10.0.1.4:7687",
  "browser_url": "http://10.0.1.4:7474",
  "bloom_url": null,
  "outputs": { ... },
  "created_at": "2025-01-16T14:35:22.123456Z"
}
```

### Common Issues

**Issue:** "Template file not found"
**Solution:** Ensure you're running from `localtests/` directory

**Issue:** "Azure CLI not found"
**Solution:** Install Azure CLI and run `az login`

**Issue:** "Deployment failed: QuotaExceeded"
**Solution:** Reduce VM size or request quota increase in Azure portal

**Issue:** "Artifact URL validation failed"
**Solution:** Ensure your Git branch is pushed to GitHub

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

**Implementation Status & Roadmap:**
- `marketplace/neo4j-enterprise/SIMPLE_PROPOSAL_v2.md` - Current simplified roadmap with phase completion status
- `marketplace/neo4j-enterprise/SCRIPT_PROPOSAL.md` - Original detailed specification
- `marketplace/neo4j-enterprise/SCRIPT_PROPOSAL_v2.md` - Intermediate roadmap

**Current Progress:**
- Phase 1-5: ✅ Complete (setup, config, validation, deployment)
- Phase 6-7: ⏳ Next (testing, cleanup) - 4-6 hours to MVP
- Phase 8-10: 📋 Future enhancements

## Architecture

The testing suite is built with:
- **Python 3.12+** with type hints throughout
- **Pydantic** for data validation and models
- **Typer** for CLI framework with Rich formatting
- **Rich** for beautiful terminal output
- **Azure CLI** for all Azure operations (no Python SDK)

### Key Modules

```
src/
├── config.py          # Configuration management
├── setup.py           # Interactive setup wizard
├── models.py          # Pydantic data models
├── deployment.py      # Parameter generation
├── orchestrator.py    # Deployment execution (Phase 5)
├── monitor.py         # Live status monitoring (Phase 5)
├── validation.py      # Template validation
├── resource_groups.py # RG lifecycle management
├── password.py        # Password strategies
└── utils.py           # Utility functions
```
