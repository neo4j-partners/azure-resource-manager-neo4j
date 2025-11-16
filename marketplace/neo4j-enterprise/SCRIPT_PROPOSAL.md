# ARM Template Testing Script Proposal

## Implementation Status

### ✅ Completed Phases

**Phase 1: Initial Setup and Configuration** - ✅ COMPLETE
- ✅ Project initialization with uv (Python 3.12, pyproject.toml, dependencies)
- ✅ Pydantic models for Settings, Scenarios, and DeploymentState
- ✅ Configuration management (load/save YAML configs)
- ✅ Interactive setup wizard with 10 steps
- ✅ First-run detection
- ✅ Directory structure creation
- ✅ Example template generation
- ✅ Git integration (branch detection, remote URL parsing)
- ✅ Azure subscription detection
- ✅ Password strategy configuration
- ✅ README generation

**Implementation Details:**
- Modular code structure with separate files:
  - `src/constants.py` - Configuration constants
  - `src/models.py` - Pydantic data models with validation
  - `src/utils.py` - Utility functions (Git, Azure CLI, file operations)
  - `src/config.py` - Configuration management
  - `src/setup.py` - Interactive setup wizard with Rich UI
  - `test-arm.py` - Main CLI entry point with Typer
- All paths use `localtests/.arm-testing/` structure
- Clean separation of concerns following Python best practices

**Phase 2: Core Deployment Engine** - ✅ COMPLETE
- ✅ Password management with 4 strategies (generate, environment, Key Vault, prompt)
- ✅ Artifact URL construction from Git context
- ✅ Artifact URL validation (HTTP HEAD request to verify scripts exist)
- ✅ Parameter file generation from base template + scenario overrides
- ✅ Dynamic value injection (_artifactsLocation, adminPassword)
- ✅ Parameter validation (node count, read replica compatibility)
- ✅ Timestamped parameter file storage
- ✅ Resource group and deployment name generation
- ✅ CLI integration with Typer framework
- ✅ Command-line overrides (--region, --artifacts-location)
- ✅ Beautiful deployment plan tables with Rich

**Implementation Details:**
- New modules:
  - `src/password.py` - PasswordManager class with caching
  - `src/deployment.py` - DeploymentEngine and DeploymentPlanner classes
- Enhanced `src/utils.py` with:
  - `construct_artifact_url()` - Auto-detect Git context
  - `validate_artifact_url()` - HTTP validation of scripts
- Updated `test-arm.py`:
  - Migrated from argparse to Typer for modern CLI
  - Full `deploy` command implementation
  - Support for --scenario, --all, --dry-run, --region, --artifacts-location
- Generated parameter files include all ARM template parameters
- Password caching for multi-scenario deployments
- Comprehensive error handling and validation

### 🚧 In Progress

None currently

### 📋 Pending Phases

- Phase 3: Pre-Deployment Validation
- Phase 4: Resource Group Management
- Phase 5: Deployment Execution
- Phase 6: Post-Deployment Testing
- Phase 7: Cleanup and Resource Management
- Phase 8: Reporting and Logging
- Phase 9: Interactive CLI Interface (partially complete - structure exists)
- Phase 10: Advanced Features

---

## Overview

This document proposes a Python-based testing script that automates the entire lifecycle of testing Neo4j Enterprise ARM templates. The script will use Azure CLI commands exclusively, provide interactive setup, and implement smart defaults to eliminate manual configuration.

---

## Design Philosophy

### Core Principles

1. **Interactive First-Run Experience** - If configuration doesn't exist, guide users through setup with prompts
2. **Smart Defaults** - Use timestamps, Git context, and conventions to minimize required input
3. **Azure CLI Native** - Execute all Azure operations via `az` commands, not Python SDKs
4. **Phased Implementation** - Build the script incrementally across logical phases
5. **Gitignore-Friendly** - Store all working files in a dedicated directory that can be excluded from version control
6. **Zero Code in Proposal** - All descriptions use plain English only

---

## Typical Workflow

All commands are run from within the `localtests/` directory:

```
cd localtests/
uv run test-arm.py setup        # First-time setup (interactive)
uv run test-arm.py validate     # Validate templates
uv run test-arm.py deploy --all # Deploy all test scenarios
uv run test-arm.py status       # Check deployment status
uv run test-arm.py cleanup --all # Clean up resources
```

The script manages all files within `localtests/.arm-testing/` and uses the Azure CLI (`az` commands) for all Azure operations.

---

## Directory Structure

### Testing Directory Location

All testing functionality will be in a dedicated directory at repository root:
```
/localtests/
```

Users will `cd localtests/` and run all commands from within this directory, keeping the testing infrastructure modular and isolated from the main codebase.

### Project Setup with uv

The `localtests/` directory will be initialized as a uv project with:
- **pyproject.toml** - Python version, dependencies, and project metadata
- **uv.lock** - Locked dependency versions for reproducibility
- **.venv/** - Virtual environment (git-ignored by uv)
- **test-arm.py** - Main testing script
- **README.md** - Testing documentation
- **.arm-testing/** - All temporary files, config, and working data (git-ignored)

### Subdirectory Organization

Within `localtests/.arm-testing/`, create this structure:

- **config/** - User configuration and scenario definitions
- **state/** - Active deployment tracking and history
- **params/** - Generated parameter files for deployments
- **results/** - Test outputs, reports, and deployment metadata
- **logs/** - Timestamped execution logs
- **cache/** - Downloaded neo4jtester binary and other cached files
- **templates/** - Configuration templates and examples

All paths in the script are relative to the `.arm-testing/` subdirectory within `localtests/`.

### Python Project Configuration (pyproject.toml)

The project configuration will define:
- Python version constraints (requires-python = ">=3.10")
- Core dependencies (PyYAML, GitPython, requests, rich, neo4j-driver)
- Project metadata (name, version, description)
- Script entry points

---

## Phase 1: Initial Setup and Configuration ✅ IMPLEMENTED

### Implementation Summary

Phase 1 has been fully implemented with a clean, modular architecture using Pydantic for validation and Rich for beautiful terminal UI.

### Implemented Components

#### 1. Project Structure (`localtests/`)
```
localtests/
├── src/
│   ├── __init__.py           # Package initialization with version
│   ├── constants.py          # All configuration constants and defaults
│   ├── models.py             # Pydantic data models with validation
│   ├── utils.py              # Utility functions (Git, Azure CLI, file I/O)
│   ├── config.py             # Configuration management (load/save/validate)
│   └── setup.py              # Interactive setup wizard with Rich UI
├── test-arm.py               # Main CLI entry point
├── pyproject.toml            # Project metadata and dependencies
├── uv.lock                   # Locked dependencies for reproducibility
└── .venv/                    # Virtual environment (git-ignored)
```

#### 2. Pydantic Data Models (`src/models.py`)

**Settings Model:**
- Azure subscription ID and name
- Default region, resource group prefix
- Cleanup mode (enum with validation)
- Cost limits, deployment timeouts
- Git settings (auto-detect, org, repo)
- Password strategy (enum)
- Owner email for tagging

**TestScenario Model:**
- Node count, VM sizes, disk sizes
- Neo4j version with validation
- Read replica configuration (4.4 only - validated)
- License type, plugin settings
- Field validators ensure parameter compatibility

**DeploymentState Model:**
- Deployment ID, resource group, scenario
- Timestamps (created, expires)
- Status tracking (pending/deploying/succeeded/failed/deleted)
- Test results (passed/failed/not-run)

**Enums:**
- `CleanupMode`: immediate, on-success, manual, scheduled
- `PasswordStrategy`: generate, environment, azure-keyvault, prompt

#### 3. Configuration Management (`src/config.py`)

**ConfigManager Class:**
- `is_initialized()`: Check if setup has been run
- `initialize_directories()`: Create `.arm-testing/` structure
- `load_settings()`: Load and validate settings from YAML
- `save_settings()`: Save settings with enum serialization
- `load_scenarios()`: Load and validate scenarios
- `save_scenarios()`: Save scenarios with validation
- `create_example_templates()`: Generate example configs

**Features:**
- Automatic Pydantic validation on load
- Enum serialization using `mode='json'`
- Clear error messages for invalid configs
- Example template generation

#### 4. Utility Functions (`src/utils.py`)

**Git Integration:**
- `get_git_branch()`: Detect current branch
- `get_git_remote_url()`: Get origin URL
- `parse_github_url()`: Extract org/repo from URL

**Azure CLI Integration:**
- `get_az_account_info()`: Get subscription info via `az account show`
- `get_az_default_location()`: Detect default region from `az configure`
- `get_git_user_email()`: Get email for resource tagging

**File Operations:**
- `load_yaml()` / `save_yaml()`: YAML file handling
- `load_json()` / `save_json()`: JSON file handling
- `ensure_directory()`: Safe directory creation

**Other:**
- `run_command()`: Subprocess wrapper for shell commands
- `get_timestamp()`: Consistent timestamp formatting

#### 5. Interactive Setup Wizard (`src/setup.py`)

**SetupWizard Class with 10 Steps:**

1. **Welcome Message**: Rich Panel with overview and confirmation
2. **Azure Subscription Detection**:
   - Runs `az account show`
   - Displays subscription info in Rich Table
   - Confirms usage
3. **Default Region Selection**:
   - Auto-detects from `az configure --list-defaults`
   - Offers quick confirmation if detected
   - Numbered menu with smart default
   - Custom entry option
4. **Resource Naming**: Configure prefix (default: neo4j-test)
5. **Cleanup Behavior**: Select from 4 modes with explanations
6. **Cost Safety Limits**: Optional cost threshold configuration
7. **Test Scenarios**: Option to create 3 default scenarios
8. **Git Integration**: Auto-detect branch/repo for artifact URLs
9. **Password Strategy**: 4 options with recommendations
10. **Finalize**:
    - Display configuration summary in Rich Table
    - Confirm and save
    - Create directory structure
    - Generate example templates
    - Update README.md

**Features:**
- Rich UI with colored output, tables, panels
- Smart defaults throughout
- Validation at each step
- Clear error messages
- Graceful handling of missing tools (Git, Azure CLI)

#### 6. Main CLI (`test-arm.py`)

**Features:**
- Command parser with usage help
- First-run detection (auto-triggers setup)
- Setup command implementation
- Stubs for future commands (validate, deploy, test, status, cleanup, report)
- Comprehensive error handling
- Keyboard interrupt handling
- Rich formatted help text

**Commands Implemented:**
- ✅ `setup`: Run interactive setup wizard
- 🚧 `validate`: Template validation (placeholder)
- 🚧 `deploy`: Deployment orchestration (placeholder)
- 🚧 `test`: Test existing deployment (placeholder)
- 🚧 `status`: Show active deployments (placeholder)
- 🚧 `cleanup`: Resource cleanup (placeholder)
- 🚧 `report`: Generate reports (placeholder)

#### 7. Dependencies (`pyproject.toml`)

```toml
[project]
name = "neo4j-arm-testing"
version = "0.1.0"
requires-python = ">=3.12"
dependencies = [
    "pydantic>=2.12.4",      # Data validation
    "pyyaml>=6.0.3",         # YAML file handling
    "gitpython>=3.1.45",     # Git integration
    "requests>=2.32.5",      # HTTP requests
    "rich>=14.2.0",          # Beautiful terminal UI
    "neo4j-driver>=5.28.2",  # Neo4j connectivity (future)
]
```

### Files Created After Setup

**Configuration:**
- `.arm-testing/config/settings.yaml` - User settings
- `.arm-testing/config/scenarios.yaml` - Test scenarios

**Examples:**
- `.arm-testing/templates/settings.example.yaml` - Example settings
- `.arm-testing/templates/scenarios.example.yaml` - Example scenarios

**Documentation:**
- `README.md` - Quick start guide

### Code Quality Features

✅ **Type Safety**: Full type hints throughout
✅ **Validation**: Pydantic models with field validators
✅ **Modularity**: Clean separation of concerns
✅ **Error Handling**: Graceful error messages
✅ **Documentation**: Comprehensive docstrings
✅ **User Experience**: Rich UI with colors and tables
✅ **Smart Defaults**: Auto-detection of Git and Azure settings
✅ **Compatibility**: Works without Git or specific Azure config

### Testing the Implementation

```bash
cd localtests/

# Show usage
uv run test-arm.py

# Run interactive setup
uv run test-arm.py setup

# Check created files
ls -la .arm-testing/config/
cat .arm-testing/config/settings.yaml
cat .arm-testing/config/scenarios.yaml
```

### Known Limitations & Future Improvements

1. **No validation of Azure regions**: Accepts any string as region
2. **Limited Azure CLI error handling**: Could provide more specific guidance
3. **No config migration**: If models change, manual config updates needed
4. **Single config file**: No support for multiple profiles/environments

**Phase 2: Core Deployment Engine** - ✅ COMPLETE

### Implementation Summary

Implemented parameter file generation, password management, and Git-based artifact detection with full CLI integration using Typer.

### Implemented Components

#### 1. Password Management (`src/password.py`)

**PasswordManager Class:**
- Generate: Random 24-char secure passwords with Azure requirements
- Environment: Read from NEO4J_ADMIN_PASSWORD with validation
- Azure Key Vault: Retrieve via az CLI from specified vault
- Prompt: Interactive secure input with complexity validation
- Password caching for multi-scenario deployments

#### 2. Deployment Engine (`src/deployment.py`)

**DeploymentEngine Class:**
- Load base parameters from marketplace template
- Apply scenario-specific overrides (nodeCount, vmSize, version, plugins)
- Inject dynamic values (_artifactsLocation, adminPassword)
- Validate parameter combinations (read replicas only with 4.4)
- Generate timestamped parameter files

**DeploymentPlanner Class:**
- Generate unique deployment IDs (UUID)
- Create resource group names: `{prefix}-{scenario}-{timestamp}`
- Create deployment names: `neo4j-deploy-{scenario}-{timestamp}`
- Handle Azure naming constraints (max 90/64 chars)

#### 3. Enhanced Utilities (`src/utils.py`)

**New Functions:**
- `construct_artifact_url()`: Auto-detect Git branch/org/repo for raw.githubusercontent.com URLs
- `validate_artifact_url()`: HTTP HEAD request to verify scripts exist

#### 4. CLI with Typer (`test-arm.py`)

**Migrated to Typer v0.20.0:**
- Modern decorator-based commands with type hints
- Auto-generated help with Rich formatting
- Built-in validation (ranges, mutual exclusion)

**Deploy Command:**
- `--scenario <name>` / `--all` for scenario selection
- `--region`, `--artifacts-location` overrides
- `--dry-run` for parameter generation without deployment
- Beautiful deployment plan tables
- Error messages show available scenarios

### Testing Results

✅ Single scenario parameter generation
✅ All scenarios with password caching
✅ Command-line overrides (region, artifacts)
✅ URL validation with helpful error messages
✅ Proper error handling for invalid scenarios

**Phase 3: Pre-Deployment Validation** - ✅ COMPLETE

### Implementation Summary

Implemented ARM template validation, what-if analysis, and cost estimation before deployment.

### Implemented Components

#### 1. Template Validation (`src/validation.py`)

**TemplateValidator Class:**
- `validate_template()`: Validate using `az deployment group validate`
- `what_if_analysis()`: Preview changes with `az deployment group what-if`
- `display_what_if_results()`: Formatted tables showing creates/modifies/deletes
- Pydantic models: ValidationResult, WhatIfResult, WhatIfResource
- Parse and display Azure CLI JSON responses
- Handle validation errors with clear messages

**CostEstimator Class:**
- Simple pricing table for common Azure resources
- `estimate_cost()`: Calculate hourly costs for VMs, disks, LB, IPs
- `display_cost_estimate()`: Rich table with cost breakdown
- Compare against configured cost limit
- Support 1-hour default duration estimation

#### 2. Resource Group Management (`src/resource_groups.py`)

**ResourceGroupManager Class:**
- `create_resource_group()`: Create RG with tags via `az group create`
- `delete_resource_group()`: Delete RG with optional --no-wait
- `resource_group_exists()`: Check existence with `az group exists`
- `generate_tags()`: Standardized tags (purpose, scenario, branch, owner, etc.)
- `save_deployment_state()`: Track deployments in JSON state file
- `load_all_deployment_states()`: Load tracked deployments
- `update_deployment_status()`: Update deployment/test status
- `list_managed_resource_groups()`: Query Azure for managed RGs
- `find_orphaned_resources()`: Detect untracked RGs in Azure
- `find_expired_deployments()`: Find deployments past expiration

**State Tracking:**
- JSON file: `.arm-testing/state/active-deployments.json`
- Pydantic DeploymentState model with validation
- UUID deployment IDs for unique tracking

#### 3. CLI Integration (`test-arm.py`)

**Validate Command:**
- `--scenario <name>` for specific scenario validation
- `--skip-what-if` to skip what-if analysis (faster)
- Auto-creates validation RG (`arm-validation-temp`) if needed
- Validates all scenarios by default
- Shows cost estimates with limit warnings
- Exit code 1 if any validation fails

### Features

✅ ARM template syntax validation
✅ What-if analysis with resource change preview
✅ Cost estimation per resource type
✅ Cost limit enforcement warnings
✅ Beautiful Rich tables for results
✅ Resource group lifecycle management
✅ Standardized tagging (8 tags)
✅ State file tracking with Pydantic validation
✅ Orphan and expiration detection

**Phase 4: Resource Group Management** - ✅ COMPLETE

Implemented as part of Phase 3 (see ResourceGroupManager above). Provides full resource group lifecycle management, tagging, and state tracking.

---

## Phase 5: Deployment Execution

### Module 7: Deployment Orchestrator

This module should:

#### Generate Unique Deployment Names
- Use pattern: `neo4j-deploy-{scenario}-{timestamp}`
- Example: `neo4j-deploy-standalone-v5-20250116-143052`

#### Execute Deployment with No-Wait
- Execute: `az deployment group create --resource-group {rg-name} --name {deploy-name} --template-file mainTemplate.json --parameters @{param-file} --no-wait`
- The `--no-wait` flag allows parallel deployments

#### Track Multiple Deployments
- Maintain list of in-flight deployment names and resource groups
- Support configurable parallelism (default: 3 concurrent deployments)
- Queue additional deployments if parallel limit reached

#### Handle Deployment Submission Errors
- Parse `az` command output for errors
- Common errors: quota exceeded, invalid parameters, permission denied
- Display clear error messages and fail gracefully

### Module 8: Deployment Monitor

This module should:

#### Poll Deployment Status
- For each active deployment, periodically execute: `az deployment group show --resource-group {rg-name} --name {deploy-name} --query "properties.provisioningState"`
- Parse states: Running, Succeeded, Failed, Canceled
- Update internal tracking

#### Display Live Status Dashboard
- Create terminal UI showing table of all deployments
- Columns: Scenario, Resource Group, Status, Duration, Progress
- Update display every 30 seconds
- Use color coding: green for succeeded, red for failed, yellow for running

#### Detect Completion
- When state changes to Succeeded or Failed, mark deployment as complete
- Record completion timestamp
- Calculate total deployment duration

#### Handle Timeouts
- Track deployment start time
- Compare against configured timeout (default: 30 minutes)
- If timeout exceeded, mark deployment as failed-timeout
- Note: Do not delete the deployment, allow investigation

#### Stream Error Details on Failure
- When deployment fails, execute: `az deployment operation group list --resource-group {rg-name} --name {deploy-name}`
- Parse operation details to identify which resource failed
- Display error message and status code
- Save full error output to log file

---

## Phase 6: Post-Deployment Testing

### Module 9: Output Extractor

This module should:

#### Retrieve Deployment Outputs
- Execute: `az deployment group show --resource-group {rg-name} --name {deploy-name} --query "properties.outputs"`
- Parse JSON output structure

#### Extract Key Values
- Neo4jBrowserURL or Neo4jClusterBrowserURL (depending on nodeCount)
- Neo4jBloomURL if Bloom was installed
- Username (always "neo4j")

#### Save to Results File
- Write outputs to: `.arm-testing/results/outputs-{scenario}-{timestamp}.json`
- Include full output structure
- Add metadata: deployment name, resource group, scenario, timestamp

#### Generate Connection Information
- Parse Browser URL to extract hostname and port
- Convert HTTP URL to Neo4j protocol: replace `http://` with `neo4j://` and port `7474` with `7687`
- Format connection string: `neo4j://{hostname}:7687`

### Module 10: Neo4j Connectivity Tester

This module should:

#### Download Neo4jtester Binary
- Check if `.arm-testing/cache/neo4jtester_linux` exists
- If not, download from: `https://github.com/neo4j/neo4jtester/raw/main/build/neo4jtester_linux`
- Make executable: `chmod +x`
- Cache for future runs

#### Execute Neo4jtester
- Retrieve connection URI from output extractor
- Retrieve password based on configuration (from generated value, env var, or prompt)
- Determine edition: "Enterprise" or "Evaluation" based on scenario configuration
- Execute: `.arm-testing/cache/neo4jtester_linux "{uri}" "neo4j" "{password}" "{edition}"`

#### Parse Test Results
- Capture stdout and stderr from neo4jtester
- Parse exit code (0 = success, non-zero = failure)
- Extract test summary (connection test, edition verification, basic queries)

#### Record Test Status
- Update state file with test result: passed/failed
- Save neo4jtester output to: `.arm-testing/logs/neo4jtest-{scenario}-{timestamp}.log`
- Include test output in final report

### Module 11: Extended Validation (Optional Phase)

This module should:

#### Cluster Health Check (For Multi-Node Deployments)
- If nodeCount >= 3, verify cluster status
- Options:
  - Use neo4j-driver Python library to execute: `CALL dbms.cluster.overview()`
  - Parse results to confirm all nodes are ONLINE
  - Verify leader election occurred

#### Plugin Verification
- If Graph Data Science installed, verify plugin loaded
  - Execute query: `CALL gds.list()`
- If Bloom installed, check Bloom endpoint accessibility
  - HTTP request to Neo4jBloomURL

#### Sample Workload Execution
- Execute basic CRUD operations:
  - CREATE nodes
  - CREATE relationships
  - Query data
  - DELETE test data
- Measure query response times
- Verify data consistency

#### Security Configuration Check
- Verify expected ports are open (7474, 7687, 7473)
- Check that SSH port 22 is accessible (for debugging)
- Confirm HTTPS endpoint responds (7473)

---

## Phase 7: Cleanup and Resource Management

### Module 12: Cleanup Orchestrator

This module should:

#### Determine Cleanup Action
- Based on configured cleanup mode and test result:
  - **immediate**: Always delete
  - **on-success**: Delete if tests passed, keep if failed
  - **manual**: Never auto-delete
  - **scheduled**: Tag with expiration, delete later

#### Execute Resource Group Deletion (When Applicable)
- Execute: `az group delete --name {rg-name} --yes --no-wait`
- Use `--no-wait` to avoid blocking on deletion
- Deletion can take 5-10 minutes

#### Update State File
- Mark deployment as deleted in state file
- Record deletion timestamp
- Move entry to deletion history

#### Manual Cleanup Command
- Support explicit cleanup: `python test-arm.py cleanup --deployment {id}`
- Support cleanup by age: `python test-arm.py cleanup --older-than 24h`
- Support cleanup all: `python test-arm.py cleanup --all`

#### Orphan Detection
- Query Azure for resource groups with tag `managed-by=test-arm-script`
- Compare against state file
- Identify orphans: Azure resource groups not in state file, or state entries without Azure resources
- Prompt to clean up orphans

#### Scheduled Cleanup
- Implement background cleanup for expired resources
- Query resource groups where `expires` tag is past current time
- Prompt for confirmation before deletion
- Generate cleanup report

#### Safety Confirmations
- For production subscriptions (detected by name patterns), require double confirmation
- Display cost impact of resources being deleted
- Allow dry-run mode: show what would be deleted without deleting

---

## Phase 8: Reporting and Logging

### Module 13: Report Generator

This module should:

#### Collect Deployment Summary Data
- For each deployment:
  - Scenario name
  - Resource group name
  - Start and end timestamps
  - Total duration
  - Deployment status (succeeded/failed/timeout)
  - Test status (passed/failed/not-run)
  - Error messages if applicable

#### Generate Markdown Report
- Create file: `.arm-testing/results/report-{timestamp}.md`
- Include sections:
  - Executive summary (total deployments, pass rate, duration)
  - Deployment details table
  - Failed deployments with error details
  - Links to Azure portal for each deployment
  - Cost estimates per deployment
  - Recommendations based on failures

#### Generate HTML Report (Optional)
- Convert Markdown to HTML with styling
- Include charts: pass/fail pie chart, duration bar chart
- Embed logs and outputs inline
- Make shareable as single file

#### Generate JUnit XML (For CI/CD)
- Format test results as JUnit XML
- Each scenario is a test case
- Include duration, status, error messages
- Compatible with Azure DevOps, Jenkins, GitHub Actions

#### Historical Tracking
- Append summary to: `.arm-testing/state/history.jsonl` (JSON Lines format)
- Each line is one test run
- Enables trend analysis over time

### Module 14: Logging System

This module should:

#### Create Timestamped Log Files
- Main log: `.arm-testing/logs/run-{timestamp}.log`
- Per-deployment logs: `.arm-testing/logs/deploy-{scenario}-{timestamp}.log`

#### Log Levels
- DEBUG: All az command executions and outputs
- INFO: Major steps (starting deployment, tests passed)
- WARNING: Non-fatal issues (cost threshold approached)
- ERROR: Failures and exceptions

#### Log All Azure CLI Commands
- Before executing each `az` command, log the full command
- After execution, log exit code and output (truncated if very long)
- This enables reproducing issues manually

#### Structured Logging
- Use JSON-formatted log entries for machine parsing
- Include: timestamp, level, module, message, metadata
- Allows querying logs programmatically

#### Console Output
- Display simplified progress to terminal
- Use colors and formatting for readability
- Verbose mode shows full logs in real-time

---

## Phase 9: Interactive CLI Interface

### Module 15: Command Parser

This module should:

#### Define Command Structure

**Validate Command**
- Description: Validate templates without deploying
- Syntax: `python test-arm.py validate`
- Actions: Run validation and what-if for all scenarios, display results

**Deploy Command**
- Description: Deploy one or more scenarios
- Syntax: `python test-arm.py deploy [--scenario NAME | --all] [options]`
- Options:
  - `--scenario NAME`: Deploy single scenario
  - `--all`: Deploy all configured scenarios
  - `--region REGION`: Override default region
  - `--cleanup-mode MODE`: Override cleanup behavior
  - `--dry-run`: Preview without deploying
  - `--parallel N`: Max concurrent deployments

**Test Command**
- Description: Test an existing deployment
- Syntax: `python test-arm.py test DEPLOYMENT_ID`
- Actions: Run neo4jtester against specified deployment

**Status Command**
- Description: Show active deployments
- Syntax: `python test-arm.py status`
- Actions: Display table of active deployments and their status

**Cleanup Command**
- Description: Clean up resources
- Syntax: `python test-arm.py cleanup [--deployment ID | --all | --older-than DURATION]`
- Actions: Delete specified resources

**Report Command**
- Description: Generate test report
- Syntax: `python test-arm.py report [DEPLOYMENT_ID]`
- Actions: Create report for deployment or latest run

**Setup Command**
- Description: Re-run interactive setup
- Syntax: `python test-arm.py setup`
- Actions: Walk through configuration wizard

#### Parse Command-Line Arguments
- Use argument parsing to extract command, flags, and values
- Validate argument combinations
- Display help text for invalid usage

#### Interactive Prompts During Execution
- When password needed but not configured, prompt securely
- When destructive action requested, ask for confirmation
- When multiple options exist, present numbered menu

#### Progress Indicators
- Show spinner during long operations
- Display progress bars for deployments with estimated time remaining
- Update status in real-time for monitoring

#### Colorized Output
- Use green for success messages
- Use red for errors
- Use yellow for warnings
- Use blue for informational messages
- Respect NO_COLOR environment variable

---

## Phase 10: Advanced Features

### Module 16: Parallel Deployment Manager

This module should:

#### Implement Deployment Queue
- Maintain queue of scenarios to deploy
- Process queue with configurable parallelism
- Support priority ordering (fast scenarios first)

#### Resource Limit Detection
- Before starting deployment, check Azure quotas
- Execute: `az vm list-usage --location {region}`
- Parse output to identify available VM quota
- Calculate required VMs for deployment
- Abort if quota insufficient

#### Intelligent Scheduling
- Distribute deployments across regions to avoid quota conflicts
- Stagger start times to avoid simultaneous validation storms
- Group scenarios by VM size for efficient quota usage

### Module 17: Cost Tracking

This module should:

#### Query Azure Cost Management
- After deployments complete, wait for cost data to populate (can take hours)
- Execute: `az consumption usage list --start-date {date} --end-date {date}`
- Filter by resource group name
- Parse actual costs incurred

#### Compare Estimates vs Actuals
- Cross-reference estimated costs with actual Azure billing data
- Calculate variance percentage
- Improve cost estimation model based on historical data

#### Generate Cost Report
- Breakdown costs by resource type
- Show cumulative testing costs over time
- Alert if monthly testing budget exceeded

### Module 18: Template Diffing

This module should:

#### Compare Template Versions
- If testing on feature branch, diff against main branch template
- Execute: `git diff main -- marketplace/neo4j-enterprise/mainTemplate.json`
- Parse diff output to identify changed resources

#### Highlight Impactful Changes
- Identify new resources being added
- Identify resources being modified
- Identify resources being removed
- Flag breaking changes (parameter removals)

#### Smart Test Selection
- If only scripts changed, skip what-if analysis
- If only documentation changed, skip deployment entirely
- If resources changed, run full validation

---

## Implementation Phases Summary

### Phase 1: Foundation
- Setup wizard with interactive prompts
- Configuration file generation
- Directory structure creation
- Smart defaults for all settings

### Phase 2: Core Engine
- Configuration loading and merging
- Git branch detection and artifact URL construction
- Parameter file generation with scenario overrides

### Phase 3: Validation
- Template syntax validation using `az` commands
- What-if analysis and resource preview
- Cost estimation and limit enforcement

### Phase 4: Resource Management
- Resource group creation with timestamp-based names
- Standardized tagging for tracking
- State file management

### Phase 5: Deployment
- Parallel deployment orchestration with `--no-wait`
- Real-time monitoring and status dashboard
- Timeout handling and error detection

### Phase 6: Testing
- Output extraction from deployments
- Neo4jtester integration
- Optional extended validation (cluster health, plugins)

### Phase 7: Cleanup
- Multiple cleanup modes (immediate, on-success, manual, scheduled)
- Orphan detection and cleanup
- Safety confirmations for production

### Phase 8: Reporting
- Markdown and HTML report generation
- JUnit XML for CI/CD integration
- Historical tracking and trend analysis
- Comprehensive logging

### Phase 9: CLI Interface
- Command structure (validate, deploy, test, status, cleanup, report, setup)
- Interactive prompts and confirmations
- Progress indicators and colorized output

### Phase 10: Advanced Features
- Intelligent parallel deployment management
- Azure cost tracking and variance analysis
- Template diffing and smart test selection

---

## File Organization

All files are created within the `localtests/` directory. The script operates from within `localtests/` and all paths below are relative to that directory.

### Files Created by Script

#### Project Files (Version Controlled)
- `test-arm.py` - Main testing script
- `pyproject.toml` - Python project configuration with dependencies
- `uv.lock` - Locked dependency versions
- `README.md` - Testing suite documentation

#### Working Files (All within `.arm-testing/`, Git-Ignored)

**Configuration Files:**
- `.arm-testing/config/settings.yaml` - User settings
- `.arm-testing/config/scenarios.yaml` - Test scenario definitions
- `.arm-testing/templates/settings.example.yaml` - Example configuration template
- `.arm-testing/templates/scenarios.example.yaml` - Example scenarios template

**State Files:**
- `.arm-testing/state/active-deployments.json` - Currently running/deployed resources
- `.arm-testing/state/history.jsonl` - Historical test run data

**Generated Files:**
- `.arm-testing/params/params-{scenario}-{timestamp}.json` - Generated parameter files
- `.arm-testing/results/outputs-{scenario}-{timestamp}.json` - Deployment outputs
- `.arm-testing/results/report-{timestamp}.md` - Test reports
- `.arm-testing/logs/run-{timestamp}.log` - Execution logs
- `.arm-testing/logs/deploy-{scenario}-{timestamp}.log` - Per-deployment logs
- `.arm-testing/logs/neo4jtest-{scenario}-{timestamp}.log` - Test outputs
- `.arm-testing/cache/neo4jtester_linux` - Cached test binary

**Virtual Environment (Git-Ignored by uv):**
- `.venv/` - Python virtual environment

### Gitignore Configuration

The repository root `.gitignore` already includes `.arm-testing/` which covers `localtests/.arm-testing/`. All temporary files, configuration, logs, and working data are automatically git-ignored.

---

## Smart Defaults Reference

### Naming Conventions

| Component | Pattern | Example |
|-----------|---------|---------|
| Resource Group | `{prefix}-{scenario}-{timestamp}` | `neo4j-test-cluster-v5-20250116-143052` |
| Deployment | `neo4j-deploy-{scenario}-{timestamp}` | `neo4j-deploy-standalone-v5-20250116-143052` |
| Parameter File | `params-{scenario}-{timestamp}.json` | `params-cluster-v5-20250116-143052.json` |
| Results File | `outputs-{scenario}-{timestamp}.json` | `outputs-cluster-v5-20250116-143052.json` |
| Report File | `report-{timestamp}.md` | `report-20250116-143052.md` |
| Log File | `run-{timestamp}.log` | `run-20250116-143052.log` |

### Timestamp Format
- Format: `YYYYMMDD-HHMMSS`
- Timezone: Local system time
- Example: `20250116-143052` (January 16, 2025 at 14:30:52)

### Azure Resource Tags

| Tag Key | Value Pattern | Purpose |
|---------|---------------|---------|
| purpose | `arm-template-testing` | Identifies test resources |
| scenario | `{scenario-name}` | Links to test scenario |
| branch | `{git-branch}` | Tracks source code branch |
| created | `{iso-timestamp}` | Creation time |
| expires | `{iso-timestamp}` | Scheduled deletion time |
| owner | `{git-user-email}` | Identifies creator |
| deployment-id | `{uuid}` | Unique deployment identifier |
| managed-by | `test-arm-script` | Indicates script management |

### Default Scenario VM Sizes

| Scenario Type | Default VM Size | Rationale |
|---------------|-----------------|-----------|
| Standalone Development | Standard_E4s_v5 | Cost-effective, 4 vCPU, 32 GB RAM |
| Cluster Testing | Standard_E4s_v5 | Same as standalone for consistency |
| Performance Testing | Standard_E8s_v5 | Higher resources, 8 vCPU, 64 GB RAM |
| Read Replicas | Standard_E4s_v5 | Match primary node specs |

---

## Success Criteria

The script will be considered successful when it achieves:

1. **Zero-Config First Run** - Setup wizard completes in under 5 minutes with minimal user input
2. **Automatic Branch Detection** - Developers never manually edit parameter files for artifact location
3. **Parallel Efficiency** - Reduces total test time by 70%+ compared to sequential testing
4. **Pre-Deployment Validation** - Catches 90%+ of errors before Azure deployment starts
5. **Cost Visibility** - Always shows estimated costs before deploying resources
6. **Automatic Cleanup** - Zero orphaned resources when using on-success mode
7. **Clear Reporting** - Non-technical users can understand test results
8. **CI/CD Ready** - Generates machine-readable output for automation
9. **Error Recovery** - Gracefully handles network issues, quota limits, and partial failures
10. **Comprehensive Logging** - All Azure CLI commands logged for reproducibility

---

## Future Enhancements

### Community Contributions
- Plugin system for custom validators
- Extensible scenario templates
- Custom notification handlers

### Cloud Provider Expansion
- Support AWS CloudFormation testing (separate script)
- Support Google Cloud Deployment Manager

### Advanced Testing
- Chaos engineering: Random resource deletion during tests
- Performance benchmarking: Track query latency over time
- Security scanning: Automated vulnerability assessment

### Integration
- Slack/Teams notifications on deployment completion
- Azure DevOps pipeline integration
- GitHub Actions workflow generation
- Terraform compatibility for infrastructure comparison

---

## Conclusion

This proposal outlines a comprehensive Python testing script that:
- Uses interactive prompts for zero-config setup
- Executes all Azure operations via `az` CLI commands
- Implements smart defaults using timestamps and Git context
- Organizes all artifacts in `.arm-testing/` directory for easy gitignore
- Builds functionality across 10 logical implementation phases
- Describes all modules using plain English without code examples

The script will transform ARM template testing from a manual, error-prone process into an automated, reliable, and efficient workflow accessible to developers of all Azure experience levels.
