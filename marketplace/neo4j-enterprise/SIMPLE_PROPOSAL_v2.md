# ARM Template Testing Script - Simplified Implementation Plan

## Executive Summary

**Goal:** Create a simple, automated testing script that deploys Neo4j Enterprise ARM templates to Azure, validates they work, and cleans up resources.

**Current Status:** 60% complete (6 of 10 phases). **Deployments AND Testing now fully functional!** 🎉

**Time to MVP (Phase 7 only):** 2-3 hours of focused development remaining.

**Philosophy:** Start simple, add features later. Get the core loop working first: Deploy → Test → Cleanup.

---

## What's Been Built (Phases 1-4)

### ✅ Phase 1: Interactive Setup
A guided wizard that collects and saves all configuration needed to run tests:
- Azure subscription and default region detection
- Resource naming preferences
- Cleanup behavior selection
- Test scenario definitions
- Git branch auto-detection for artifact URLs
- Password strategy selection

**Files:** `src/setup.py`, `src/config.py`, `src/models.py`, `src/constants.py`

### ✅ Phase 2: Parameter Generation
Generates ARM template parameter files for test scenarios:
- Loads base parameters from marketplace template
- Applies scenario-specific overrides (node count, VM size, Neo4j version)
- Injects dynamic values (artifact location, admin password)
- Validates parameter combinations
- Saves timestamped parameter files

**Files:** `src/deployment.py`, `src/password.py`

### ✅ Phase 3: Pre-Deployment Validation
Validates templates before deploying to Azure:
- ARM template syntax validation
- What-if analysis showing resource changes
- Cost estimation with breakdown
- Displays results in formatted tables

**Files:** `src/validation.py`

### ✅ Phase 4: Resource Group Management
Manages Azure resource groups and deployment tracking:
- Creates resource groups with standardized tags
- Tracks deployments in state file
- Detects orphaned resources
- Identifies expired deployments

**Files:** `src/resource_groups.py`

**Working Commands:**
```bash
uv run test-arm.py setup                           # Initial configuration
uv run test-arm.py validate                        # Validate all scenarios
uv run test-arm.py deploy --scenario x --dry-run   # Generate parameters only
```

---

## What Needs to Be Built (Simplified)

### ✅ Phase 5: Deployment Execution (COMPLETE - 4-5 hours)

**Goal:** Actually deploy ARM templates to Azure and monitor their progress.

**What It Does:**
Takes generated parameter files and executes Azure deployments, tracking their status until completion or failure.

**Implementation Summary:**
Phase 5 has been fully implemented with clean, modular architecture following project best practices.

**Implemented Components:**

1. **DeploymentOrchestrator** (`src/orchestrator.py`):
   - Submits deployments with --no-wait flag
   - Extracts deployment outputs from Azure
   - Parses browser URLs to Neo4j protocol URIs
   - Saves connection information to JSON files
   - Error parsing for common failure scenarios

2. **DeploymentPlanner** (`src/orchestrator.py`):
   - Generates resource group names with timestamp
   - Generates deployment names following Azure constraints
   - Handles name length limits (90 chars for RG, 64 for deployment)

3. **DeploymentMonitor** (`src/monitor.py`):
   - Polls deployment status every 30 seconds
   - Live Rich table dashboard with real-time updates
   - Timeout detection and handling
   - Error extraction for failed deployments
   - Color-coded status display

4. **ConnectionInfo Model** (`src/models.py`):
   - Pydantic model for connection information
   - Stores Neo4j URI, browser URL, Bloom URL
   - Includes raw outputs and metadata

5. **Updated CLI** (`test-arm.py`):
   - Full integration of orchestrator and monitor
   - Creates resource groups with tags
   - Submits deployments to Azure
   - Monitors with live dashboard
   - Extracts and saves connection info
   - Deployment summary with next steps

**Todo List:**
- [x] Create deployment orchestrator module
- [x] Implement deployment submission using Azure CLI create command
- [x] Add support for no-wait flag to enable parallel deployments
- [x] Implement deployment status polling every 30 seconds
- [x] Create live status dashboard showing all deployments
- [x] Add timeout handling (default 30 minutes per deployment)
- [x] Extract and display error details when deployments fail
- [x] **When deployment succeeds, extract outputs from Azure**
- [x] **Parse deployment outputs to get browser URL and other connection info**
- [x] **Convert HTTP browser URL to Neo4j protocol connection string**
- [x] **Save connection information to results directory (connection-{scenario}-{timestamp}.json)**
- [x] Update state file with deployment status and timestamps
- [x] Add support for parallel deployment limit (default 3 concurrent)
- [x] Integrate with existing deploy command in CLI
- [x] Add proper error handling for quota exceeded and permission errors

**Success Criteria:**
- ✅ Can submit single deployment and monitor to completion
- ✅ Can run multiple deployments in parallel
- ✅ Shows live progress in terminal
- ✅ Captures and displays error messages on failure
- ✅ Updates state file correctly
- ✅ **Saves connection information file for successful deployments**

**Files Created:**
- `src/orchestrator.py` - Deployment execution and planning
- `src/monitor.py` - Status monitoring and live dashboard
- Updated `src/models.py` - Added ConnectionInfo model
- Updated `test-arm.py` - Full deployment workflow integration

---

### 🧪 Phase 6: Post-Deployment Testing (CRITICAL - 2-3 hours) ✅ COMPLETE

**Goal:** Verify that deployed Neo4j instances are actually working correctly.

**What It Does:**
Reads connection information saved by Phase 5 and runs connectivity tests using neo4jtester to validate the deployment.

**Implementation Summary:**
Created comprehensive Neo4j testing framework with automatic test execution after deployment and standalone test command. The system downloads and caches neo4jtester binary, executes tests with proper credentials, parses results, and updates deployment state with test status.

**Todo List:**
- [x] Create Neo4j tester module (`src/tester.py`)
- [x] **Read connection information from file created by Phase 5**
- [x] Download neo4jtester binary to cache directory with platform detection (Darwin/Linux/Windows)
- [x] Make binary executable (Unix-like systems)
- [x] Get password using configured password strategy
- [x] Determine Neo4j edition from scenario configuration (Enterprise or Evaluation)
- [x] Execute neo4jtester with connection URI, credentials, and edition
- [x] Parse test results and exit code
- [x] Update state file with test pass/fail status
- [x] Save test output logs to logs directory with timestamps
- [x] Display test results in terminal with clear pass/fail indication
- [x] Handle test failures gracefully with helpful error messages
- [x] Support testing existing deployments by deployment ID via `test` command
- [x] Integrate automatic testing into deploy workflow
- [x] Add TestResult Pydantic model for validation

**Success Criteria:**
- ✅ Can read connection info from Phase 5 output files
- ✅ Successfully downloads and caches neo4jtester binary
- ✅ Correctly detects platform and uses appropriate binary
- ✅ Runs neo4jtester against deployments automatically after successful deployment
- ✅ Correctly identifies test pass/fail with exit codes
- ✅ Saves detailed test logs for debugging
- ✅ Can re-test a deployment without re-deploying using `uv run test-arm.py test <deployment-id>`
- ✅ Updates deployment state with test results

**Files Created:**
- `src/tester.py` - Neo4j testing with neo4jtester binary management and execution
- Updated `src/models.py` - Added TestResult Pydantic model
- Updated `src/resource_groups.py` - Added `update_deployment_test_status()` method
- Updated `test-arm.py` - Integrated testing into deploy workflow and implemented test command

---

### 🧹 Phase 7: Cleanup Automation (CRITICAL - 2-3 hours)

**Goal:** Automatically delete Azure resources to control costs.

**What It Does:**
Implements cleanup logic based on configured mode and test results.

**Todo List:**
- [ ] Create cleanup manager module
- [ ] Implement cleanup decision logic for all modes:
  - [ ] Immediate: Always delete after deployment completes
  - [ ] On-success: Delete only if tests passed, keep failures for debugging
  - [ ] Manual: Never auto-delete, only via explicit cleanup command
- [ ] Add resource group deletion using Azure CLI with no-wait flag
- [ ] Update state file to mark deployments as deleted
- [ ] Record deletion timestamps
- [ ] Implement manual cleanup command with deployment ID parameter
- [ ] Add cleanup all command with confirmation prompt
- [ ] Add cleanup by age command (older than X hours)
- [ ] Add force flag to skip confirmations
- [ ] Add dry-run mode to preview what would be deleted
- [ ] Implement safety check: only delete resource groups with managed-by tag
- [ ] Display cleanup summary after execution

**Success Criteria:**
- Cleanup modes work correctly based on configuration
- Manual cleanup commands work for selective deletion
- Safety checks prevent accidental deletion of unmanaged resources
- State file stays accurate after cleanup

---

## Optional Enhancement Phase (After MVP)

### 📊 Phase 8: Basic Reporting (3-4 hours)

**Goal:** Generate simple reports for test runs and enable CI/CD integration.

**What It Does:**
Creates markdown summaries of test runs with deployment details and results.

**Todo List:**
- [ ] Create report generator module
- [ ] Implement markdown report generation with sections:
  - [ ] Summary statistics (total deployments, pass rate, total duration)
  - [ ] Deployment details table
  - [ ] Failed deployment details with error messages
  - [ ] Azure portal links for each deployment
- [ ] Save reports to results directory with timestamp
- [ ] Add report command to CLI
- [ ] Implement session logging to file
- [ ] Log all Azure CLI commands at debug level
- [ ] Add console output with color coding
- [ ] Implement historical tracking in JSON lines format
- [ ] Add basic JUnit XML output for CI/CD systems

**Success Criteria:**
- Generates readable markdown report after test runs
- Reports include all essential information
- Can integrate with CI/CD systems via JUnit XML

---

### 🔧 Phase 9: CLI Polish (2-3 hours)

**Goal:** Complete all CLI commands and improve user experience.

**What It Does:**
Implements remaining command stubs and adds helpful features.

**Todo List:**
- [ ] Implement status command:
  - [ ] Load all deployment states
  - [ ] Query Azure for current status
  - [ ] Display rich table with status, duration, test results
  - [ ] Show summary statistics
- [ ] Implement test command:
  - [ ] Load specific deployment by ID
  - [ ] Extract outputs
  - [ ] Run neo4jtester
  - [ ] Update state file
  - [ ] Display results
- [ ] Enhance deploy command output with progress indicators
- [ ] Add verbose flag for detailed logging
- [ ] Improve error messages with actionable suggestions
- [ ] Add command aliases for common operations
- [ ] Display helpful hints after successful operations

**Success Criteria:**
- All commands work as expected
- Clear, helpful output for all operations
- Good error messages guide users to solutions

---

## Development Phases Summary

| Phase | Priority | Status | Delivers |
|-------|----------|--------|----------|
| 5. Deployment | **CRITICAL** | ✅ COMPLETE | Actual Azure deployments + connection info |
| 6. Testing | **CRITICAL** | ✅ COMPLETE | Validation that deployments work |
| 7. Cleanup | **CRITICAL** | ⏳ Pending (2-3h) | Cost control and resource management |
| **MVP COMPLETE** | - | **2-3h remaining** | **Full working testing tool** |
| 8. Reporting | Optional | ⏳ Pending (3-4h) | Reports and CI/CD integration |
| 9. CLI Polish | Optional | ⏳ Pending (2-3h) | Enhanced user experience |
| **FULL FEATURED** | - | **7-10h remaining** | **Production-ready tool** |

---

## Critical Path to MVP

### Step 1: Phase 5 (Must Do First)
Without deployment execution, nothing can actually be tested in Azure. This is the foundation for everything else.

**Deliverable:** Can deploy ARM templates to Azure and monitor until completion.

### Step 2: Phase 6 (Must Do Second)
Need to verify that deployments actually work. Without this, we don't know if templates are valid.

**Deliverable:** Can test deployed instances and record pass/fail status.

### Step 3: Phase 7 (Must Do Third)
Need to prevent runaway Azure costs by automating cleanup of test resources.

**Deliverable:** Resources are automatically cleaned up based on test results.

### Result: Working Testing Tool
After these 3 phases, you have a complete end-to-end testing workflow that:
- Deploys ARM templates
- Validates they work
- Cleans up resources automatically

**This is production-ready for basic use.**

---

## Simplifications from Original Proposal

### What Was Removed/Deferred:
1. **Advanced password strategies** - Keep only generate and prompt, skip Key Vault integration initially
2. **Multiple report formats** - Start with just markdown, skip HTML
3. **Scheduled cleanup mode** - Support only immediate, on-success, and manual
4. **Cost tracking** - Skip actual vs estimated cost comparison
5. **Template diffing** - Skip smart test selection based on git changes
6. **VM quota checking** - Skip pre-flight quota validation
7. **Intelligent scheduling** - Skip optimization of parallel deployments
8. **Extended validation** - Skip cluster health checks and plugin verification beyond basic neo4jtester

### Why These Simplifications:
- **Faster to MVP** - Get working tool in 8-11 hours instead of 18-26 hours
- **Proven workflow first** - Validate the approach works before adding complexity
- **Easier to debug** - Fewer moving parts means easier troubleshooting
- **Add later if needed** - Can always add advanced features after core works

---

## Success Metrics

### Minimum Viable Product (After Phases 5-7)
- ✅ Can deploy all test scenarios to Azure
- ✅ Can run in parallel (3 concurrent deployments)
- ✅ Validates deployments work using neo4jtester
- ✅ Automatically cleans up resources based on test results
- ✅ Saves state for tracking deployments
- ✅ Clear error messages when things fail

### Fully Featured Product (After Phases 8-9)
- ✅ Generates markdown reports with full details
- ✅ Outputs JUnit XML for CI/CD integration
- ✅ All CLI commands implemented and polished
- ✅ Comprehensive logging for debugging
- ✅ Historical tracking of test runs

---

## Files That Will Be Created

### Phase 5 (Deployment)
- `src/orchestrator.py` - Deployment execution and parallel management
- `src/monitor.py` - Status polling and live dashboard
- `.arm-testing/results/connection-{scenario}-{timestamp}.json` - **Connection info for testing**

### Phase 6 (Testing)
- `src/neo4j_test.py` - Neo4jtester integration (reads connection files from Phase 5)
- `.arm-testing/cache/neo4jtester_linux` - Test binary (downloaded)
- `.arm-testing/logs/neo4jtest-{scenario}-{timestamp}.log` - Test logs

### Phase 7 (Cleanup)
- `src/cleanup.py` - Cleanup orchestration and logic

### Phase 8 (Reporting)
- `src/reporting.py` - Report generation
- `.arm-testing/results/report-{timestamp}.md` - Markdown reports
- `.arm-testing/results/junit-{timestamp}.xml` - CI/CD output
- `.arm-testing/state/history.jsonl` - Historical tracking
- `.arm-testing/logs/run-{timestamp}.log` - Session logs

---

## Current Working Directory Structure

```
localtests/
├── src/
│   ├── __init__.py           ✅ Complete
│   ├── constants.py          ✅ Complete
│   ├── models.py             ✅ Complete
│   ├── utils.py              ✅ Complete
│   ├── config.py             ✅ Complete
│   ├── setup.py              ✅ Complete
│   ├── password.py           ✅ Complete
│   ├── deployment.py         ✅ Complete
│   ├── validation.py         ✅ Complete
│   ├── resource_groups.py    ✅ Complete
│   ├── orchestrator.py       ✅ Complete (Phase 5)
│   ├── monitor.py            ✅ Complete (Phase 5)
│   ├── neo4j_test.py         ⏳ Phase 6
│   ├── cleanup.py            ⏳ Phase 7
│   └── reporting.py          ⏳ Phase 8
├── test-arm.py               ✅ Complete (deploy integrated in Phase 5)
├── pyproject.toml            ✅ Complete
├── uv.lock                   ✅ Complete
└── .arm-testing/
    ├── config/               ✅ Working (settings.yaml, scenarios.yaml)
    ├── state/                ✅ Working (active-deployments.json)
    ├── params/               ✅ Working (generated parameter files)
    ├── templates/            ✅ Working (example configs)
    ├── results/              ✅ Working (connection-{scenario}-{timestamp}.json)
    ├── logs/                 ⏳ Phase 6 will populate
    └── cache/                ⏳ Phase 6 will populate
```

---

## Next Immediate Steps

### If Starting Now:
1. **Read existing code** - Review `src/deployment.py` and `src/resource_groups.py` to understand current patterns
2. **Create orchestrator module** - Start with deployment submission function
3. **Test single deployment** - Deploy one scenario and monitor to completion
4. **Add monitoring** - Implement status polling and live display
5. **Test parallel deployments** - Verify multiple scenarios can run concurrently
6. **Move to Phase 6** - Once deployments work, add testing

### Don't Do Yet:
- Don't add reporting until deployments and testing work
- Don't add advanced features until MVP is proven
- Don't optimize until you have working end-to-end flow

---

## Key Design Decisions

### Keep Simple:
- Use Azure CLI commands exclusively (no Python Azure SDK)
- Store everything in JSON and YAML files (no database)
- Write to filesystem for state tracking (no external services)
- Use subprocess for all Azure interactions
- Use Rich for terminal UI (already proven in Phase 1-4)

### Follow Existing Patterns:
- Pydantic models for data validation
- Typer for CLI framework
- Rich for beautiful output
- Modular file structure in `src/`
- Comprehensive error handling

### Core Principle:
**Make it work, then make it better.**

Get the basic deploy-test-cleanup loop working first. Everything else is enhancement.

---

## Conclusion

The foundation is solid. Phases 1-4 provide excellent infrastructure for configuration, validation, and state management.

**The path to MVP is clear:**
1. Implement deployment execution (Phase 5)
2. Add post-deployment testing (Phase 6)
3. Automate cleanup (Phase 7)

**Result:** A working, production-ready ARM template testing tool in 8-11 hours of development.

Additional features (reporting, CLI polish) can be added incrementally once the core workflow is proven.

The simplified approach removes unnecessary complexity while maintaining the ability to add advanced features later if needed.
