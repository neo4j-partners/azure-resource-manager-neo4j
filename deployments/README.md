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

## Setup and Deployment Guide

### 1. Environment Setup

Before deploying, you need to set up your Azure environment and configure authentication.

#### Create Azure Service Principal

Create a service principal for automated deployments:

```bash
az ad sp create-for-rbac --name "neo4j-deployment-sp" --role Contributor --scopes /subscriptions/<your-subscription-id>
```

This command returns credentials in the format:
```json
{
  "appId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "displayName": "neo4j-deployment-sp",
  "password": "your-secret-password",
  "tenant": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
}
```

Store these credentials in `azure-credentials.json`:
```json
{
  "clientId": "appId from above",
  "clientSecret": "password from above",
  "subscriptionId": "your-subscription-id",
  "tenantId": "tenant from above"
}
```

**Note:** For interactive use, you can also authenticate with `az login` instead of using a service principal.

#### First-Time Setup

Initialize the deployment framework:

```bash
cd deployments
uv run neo4j-deploy setup
```

This command:
- Creates `.arm-testing/` directory structure
- Generates default `settings.yaml` and `scenarios.yaml`
- Sets up logging and state tracking directories

#### Verify Azure Authentication

Confirm you're logged in and using the correct subscription:

```bash
az account show
```

### 2. Deploying Clusters

#### Deploy a Specific Scenario

Deploy a single test scenario:

```bash
uv run neo4j-deploy deploy --scenario standalone-v5
```

Available scenarios (defined in `.arm-testing/config/scenarios.yaml`):
- `standalone-v5` - Single node Neo4j 5.x
- `cluster-3node-v5` - 3-node cluster Neo4j 5.x
- `cluster-5node-v5` - 5-node cluster Neo4j 5.x
- `cluster-3node-aks-v5` - AKS-based 3-node cluster

#### Deploy Multiple Scenarios

Deploy all configured scenarios:

```bash
uv run neo4j-deploy deploy --all
```

Deploy specific template type:

```bash
# Deploy all enterprise VM scenarios
uv run neo4j-deploy deploy --template enterprise

# Deploy all AKS scenarios
uv run neo4j-deploy deploy --template aks
```

#### Deploy with Custom Parameters

Override default parameters:

```bash
uv run neo4j-deploy deploy --scenario cluster-3node-v5 \
  --param nodeCount=5 \
  --param vmSize=Standard_D4s_v3
```

### 3. Viewing Deployment Status

#### Check All Deployments

View status of all tracked deployments:

```bash
uv run neo4j-deploy status
```

Output shows:
- Deployment name and scenario
- Resource group name
- Current state (deploying, succeeded, failed)
- Neo4j version and configuration
- Timestamp

#### Check Specific Deployment

View detailed status for a specific scenario:

```bash
uv run neo4j-deploy status --scenario standalone-v5
```

#### Generate Test Report

Create comprehensive deployment report:

```bash
uv run neo4j-deploy report
```

Report includes:
- Deployment success/failure rates
- Validation test results
- Performance metrics
- Resource utilization

### 4. Deleting Deployments

#### Delete Specific Deployment

Remove a single deployment and its resources:

```bash
uv run neo4j-deploy cleanup --scenario standalone-v5
```

This command:
- Deletes the Azure resource group
- Removes deployment state files
- Cleans up generated parameter files

#### Delete All Deployments

Remove all tracked deployments:

```bash
uv run neo4j-deploy cleanup --all
```

**Warning:** This deletes ALL resource groups managed by the framework. Use with caution.

#### Delete by Age

Remove deployments older than specified hours:

```bash
# Delete deployments older than 24 hours
uv run neo4j-deploy cleanup --older-than 24
```

#### Manual Cleanup

If automated cleanup fails, manually delete the resource group:

```bash
az group delete --name <resource-group-name> --yes --no-wait
```

### 5. Validation and Testing

#### Validate Bicep Templates

Lint and validate all templates without deploying:

```bash
uv run neo4j-deploy validate
```

#### Validate Deployed Cluster

After deployment, validate Neo4j connectivity and functionality:

```bash
cd deployments
uv run validate_deploy <scenario-name>
```

This test:
- Connects via Bolt protocol (port 7687)
- Verifies database is running
- Creates test data (Movies graph)
- Performs CRUD operations
- Cleans up test data

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
