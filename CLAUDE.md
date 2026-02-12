# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## CRITICAL

- The `marketplace/neo4j-enterprise/` directory is a very old template pattern and should **NOT** be referenced as an example of how to do deployments — it contains many bad practices.
- It is absolutely critical to discuss how to fix a bug with the user before proceeding with a fix. **Always ask questions and discuss with the user before making changes.** Do not jump straight into implementing a fix.
- Make ONLY the changes the user requested. Do not add, remove, or modify anything beyond what was explicitly asked for — even if it seems like an improvement. If you believe something should be changed, ask first.

## Overview

Azure infrastructure-as-code for deploying Neo4j on Azure, published to the Azure Marketplace. Two separate marketplace offers:

- **Enterprise** (`marketplace/neo4j-enterprise/`) - VM Scale Sets, 1-10 nodes, Neo4j 5.x Enterprise
- **Community Edition** (`marketplace/neo4j-ce/`) - Single VM, Neo4j CE (latest or 5.x)

All templates use Azure Bicep compiled to ARM JSON for marketplace publishing.

## Working Directory Convention

**Always run `deployments/` commands from the `deployments/` directory** (prefix with `cd deployments &&` or use `@deployments`). The CLI tool `neo4j-deploy` and all `uv run` commands expect this working directory.

## Important: Modifying the Setup Flow

When changes are needed to `uv run neo4j-deploy setup`, modify the **setup command implementation** in `deployments/src/setup.py` (the `SetupWizard` class) and related models in `deployments/src/models.py` — NOT the generated template files in `.arm-testing/templates/`.

## Common Commands

```bash
# Deployments CLI (always run from deployments/)
cd deployments
uv run neo4j-deploy setup                          # Interactive first-time config
uv run neo4j-deploy validate                       # Bicep lint + compile
uv run neo4j-deploy deploy --scenario standalone-lts  # Deploy single scenario
uv run neo4j-deploy deploy --all                   # Deploy all scenarios
uv run neo4j-deploy test                            # Neo4j connectivity + CRUD validation
uv run neo4j-deploy status                          # Check deployment status
uv run neo4j-deploy cleanup --all                   # Delete Azure resource groups
uv run neo4j-deploy deploy --scenario standalone-lts --dry-run  # Preview only

# Validate individual deployment after manual deploy
cd deployments
uv run validate_deploy <scenario-name>

# Bicep development
az bicep build --file main.bicep --outfile mainTemplate.json
az bicep build --file main.bicep   # Validate only (linter runs automatically)

# Deploy templates locally
cd marketplace/neo4j-enterprise && ./deploy.sh <resource-group-name>

# Package for Azure Marketplace
cd marketplace/neo4j-enterprise && ./makeArchive.sh   # Creates archive.zip
cd marketplace/neo4j-ce && ./makeArchive.sh

# Build CE VM image for marketplace
cd marketplace/neo4j-ce && ./makeVm.sh [resource-group] [region]

# Pre-commit hook for Bicep validation
./scripts/install-git-hooks.sh
```

## Architecture

### Bicep Template Structure (both offers)

Each marketplace offer follows the same pattern:

```
marketplace/<offer>/
├── main.bicep              # Entry point - orchestrates modules, loads cloud-init
├── main.json               # Compiled ARM JSON (for marketplace)
├── parameters.json         # Default parameters (base for deployment engine)
├── createUiDefinition.json # Azure Portal UI wizard
└── modules/                # Modular Bicep resources
```

**Enterprise modules:** network.bicep, identity.bicep, loadbalancer.bicep (conditional: 3+ nodes), vmss.bicep
**CE modules:** network.bicep, disk.bicep (zone-aware), vm.bicep

### Cloud-Init Provisioning

VM provisioning uses cloud-init YAML loaded via Bicep `loadTextContent()`:

- Enterprise: `scripts/neo4j-enterprise/cloud-init/{standalone,cluster}.yaml`
- CE: `scripts/neo4j-ce/cloud-init/standalone.yaml`

**Variable substitution pattern** in `main.bicep`:
```bicep
var cloudInitStep1 = replace(cloudInitTemplate, '${unique_string}', deploymentUniqueId)
var cloudInitStep2 = replace(cloudInitStep1, '${admin_password}', passwordBase64)
// ... chained replaces, then base64 encode for user data
```

Passwords are base64-encoded to avoid shell escaping issues, decoded in cloud-init runcmd.

### Cluster Discovery (Enterprise)

DNS-based discovery, no Azure CLI needed at runtime:
- VMSS public hostnames: `vm{i}.neo4j-{uniqueString}.{location}.cloudapp.azure.com`
- Discovery endpoints: `vm0:5000,vm1:5000,vm2:5000`

### Legacy Script

`scripts/neo4j-enterprise/node.sh` is the old bash-based provisioning (pre-cloud-init). Being replaced by cloud-init YAML.

## Testing Framework (`deployments/`)

Python CLI built with Typer + Rich + Pydantic + Neo4j driver + Azure SDK.

### Key Architecture

- **Entry point:** `deployments/neo4j_deploy.py` - Typer app
- **Commands:** `deployments/src/commands/` - Each CLI command (setup, deploy, test, validate, cleanup, status, package, report)
- **Models:** `deployments/src/models.py` - Pydantic models: `Settings`, `TestScenario`, `DeploymentState`, `Edition` enum (enterprise/community), `ScenarioCollection`
- **Config:** `deployments/src/config.py` - `ConfigManager` reads/writes YAML in `.arm-testing/config/`
- **Setup:** `deployments/src/setup.py` - `SetupWizard` interactive configuration (region, password strategy, scenarios)
- **Deployment:** `deployments/src/deployment.py` - `DeploymentEngine` generates parameter files from scenarios + base parameters.json
- **Orchestrator:** `deployments/src/orchestrator.py` - Submits ARM deployments via `az deployment group create`
- **Validation:** `deployments/src/validate_deploy.py` - `Neo4jValidator` connects via Bolt, creates Movies dataset, verifies CRUD + license

### Deployment Flow

1. `ConfigManager` loads `Settings` + `ScenarioCollection` from `.arm-testing/config/`
2. `DeploymentEngine` loads base `parameters.json` from the correct marketplace directory (resolved via `Edition` enum), applies scenario overrides, generates timestamped param file in `.arm-testing/params/`
3. `DeploymentOrchestrator` submits to Azure with `--no-wait`, `DeploymentMonitor` polls status
4. On success, `Neo4jValidator` runs connectivity + CRUD tests

### Scenario Definitions

Default scenarios (created by setup wizard):
- `standalone-lts` - Enterprise, 1 node, Neo4j 5, Evaluation license
- `cluster-lts` - Enterprise, 3 nodes, Neo4j 5, Evaluation license
- `ce-standalone-latest` - CE, 1 node, latest version, Community license

`TestScenario` model enforces: CE = 1 node only + no plugins; read replicas = Neo4j 4.4 only.

## GitHub Actions CI/CD

`.github/workflows/enterprise.yml` - Runs on PRs affecting enterprise templates. Compiles Bicep, deploys, runs `uv run validate_deploy`, cleans up.

## Key Parameters

**Enterprise:** `nodeCount` (1, 3-10), `graphDatabaseVersion` ("5"), `adminPassword` (secure), `licenseType` (Enterprise/Evaluation), `vmSize`, `diskSize`

**CE:** `graphDatabaseVersion` ("latest"/"5"), `adminPassword` (secure, 12-72 chars), `vmSize`, `diskSize` (32-4095), `useTestImage` (bool, for pre-publish testing with RHEL 9)

## Development Standards

**Bicep:** Use modules for separation. `@secure()` for passwords. Parameter descriptions required. Resource naming: `${prefix}-${resourceType}-${suffix}`. Tag all resources.

**Code style:** Prefer clarity over cleverness. No unnecessary abstraction. Complete cut-over (no compatibility layers).

**Linting:** `bicepconfig.json` enforces no hardcoded secrets, secure parameters, no secret exposure in outputs, stable resource identifiers.
