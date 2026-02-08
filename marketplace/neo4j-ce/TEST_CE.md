# Test CE: Integration Test Suite for Neo4j Community Edition on Azure

## Problem Statement

The Neo4j CE Azure deployment currently has minimal validation. The GitHub Actions workflow (`community.yml`) deploys the template, waits for HTTP readiness, and runs `validate_deploy` which only confirms Bolt connectivity, Community Edition detection, and a basic Movies CRUD cycle.

There is no dedicated test suite that validates Azure-specific infrastructure: the standalone managed disk, VM health, data persistence across VM replacement, or cloud-init idempotency. The AWS CloudFormation CE template already has a comprehensive `test_ce` suite covering connectivity, CRUD, EBS volume verification, and resilience (instance termination with data survival). The Azure CE template needs equivalent coverage.

## Proposed Solution

Create a standalone Python test suite in `test_suite/test_ce/` (at the repository root) for local validation of a CE deployment on Azure. This is a local testing tool only; it is not intended for CI integration. It will mirror the structure and test coverage of the AWS `test_ce` suite, adapted for Azure primitives (Azure SDK instead of boto3, managed disk instead of EBS, VM restart instead of ASG instance replacement).

The suite will read deployment outputs from the existing `deployments/` framework's connection info files, then execute a progressive series of checks: connectivity, CRUD operations, Azure resource verification, and data persistence through a VM restart cycle.

## Requirements

### Project Setup

- The test suite lives in `test_suite/test_ce/` at the repository root.
- It is a uv Python project with its own `pyproject.toml`, `.python-version`, and `uv.lock`.
- Python version pinned to 3.12.
- The CLI entry point is invoked as `uv run test-ce`.
- Dependencies: `neo4j` (Bolt driver), `requests` (HTTP checks), `azure-identity` and `azure-mgmt-compute` (VM and disk operations).

### Configuration

- The suite reads connection info from the existing `deployments/` framework. After deploying a CE scenario with `uv run neo4j-deploy deploy`, the framework saves a connection file to `deployments/.arm-testing/results/connection-{scenario}-{timestamp}.json`.
- The suite accepts a `--scenario` argument (e.g., `--scenario standalone-ce-latest`) and automatically locates the most recent connection file for that scenario, matching how `validate_deploy` already works.
- Alternatively, the suite accepts explicit `--uri`, `--username`, and `--password` arguments for cases where the deployment was done manually outside the framework (e.g., via `deploy.sh`).
- The connection file provides: `neo4j_uri`, `browser_url`, `username`, `password`, `resource_group`, `license_type`, `node_count`, and the raw ARM template `outputs` (which include `vmName`, `dataDiskId`, `vmId`, and network resource IDs).
- All configuration is loaded into a single immutable data class at startup. No global mutable state.

### CLI Interface

- `--scenario` argument: name of the deployment scenario. The suite looks up the most recent connection file in `deployments/.arm-testing/results/` for this scenario.
- `--uri`, `--username`, `--password` arguments: explicit connection details for manual deployments. When provided, these are used instead of `--scenario`.
- `--simple` flag: run only connectivity and CRUD tests, skip Azure resource checks and persistence tests. Useful for quick post-deploy smoke tests.
- `--timeout` flag: maximum seconds to wait for VM readiness after restart (default 600).

### Test Categories

The suite has four test categories that run in order. Each category builds on the previous one.

#### 1. Connectivity Tests

- HTTP API check: GET the Browser URL, confirm the response contains a `neo4j_version` field.
- Authentication check: POST a Cypher statement to the HTTP API with Basic Auth credentials, confirm HTTP 200.
- Bolt connectivity check: open a Bolt connection, execute `RETURN 1`, confirm the result.
- APOC plugin check: call `RETURN apoc.version()` over Bolt, confirm a version string is returned. APOC is always installed in the CE template.
- Neo4j version check: query `CALL dbms.components()` and confirm the edition is `community`.

#### 2. CRUD Operations Tests

- Create the Movies dataset (The Matrix trilogy, 8 Person nodes, 3 Movie nodes, ACTED_IN/DIRECTED/PRODUCED relationships).
- Verify the dataset by counting Movie and Person nodes (expect at least 11 total nodes).
- Clean up the dataset by deleting all Movie and Person nodes and their relationships.

#### 3. Azure Resource Verification Tests (skipped in `--simple` mode)

- Confirm the VM exists and its provisioning state is `Succeeded` using the Azure Compute SDK.
- Confirm the managed data disk exists, is in the `Attached` state, and is attached to the correct VM.
- Report disk size, storage type, and availability zone.

#### 4. Persistence and Resilience Tests (skipped in `--simple` mode)

This category validates that data survives a VM restart, exercising the cloud-init idempotency (disk reattach without reformatting, password preservation).

- Write a sentinel node: create a unique node with a UUID `test_run_id` property.
- Create the Movies dataset.
- Restart the VM using the Azure Compute SDK (`restart` operation on the VM resource). This is the Azure equivalent of the AWS test's ASG instance termination; the standalone managed disk remains attached through a restart.
- Wait for Neo4j to become reachable again on the same endpoint (poll HTTP, with configurable timeout).
- Re-run all connectivity tests to confirm the service recovered.
- Verify the sentinel node still exists with the correct `test_run_id`.
- Verify the Movies dataset still exists with the expected node count.
- Clean up the sentinel node and Movies dataset.

### Test Reporting

- Each test is wrapped in a context manager that records the test name, pass/fail status, failure message, and wall-clock duration.
- At the end of the run, print a summary table showing every test result.
- Exit code 0 if all tests passed, exit code 1 if any test failed.
- All output uses Python `logging` (not print) for structured, consistent formatting.

### Source Code Organization

The source code is organized into focused, single-responsibility modules inside `src/test_ce/`:

- `cli.py` - argument parsing, orchestration of the test flow, exit code handling.
- `config.py` - connection file loading (from `deployments/.arm-testing/results/` or explicit CLI args), immutable configuration data class, Neo4j driver context manager.
- `neo4j_checks.py` - connectivity tests (HTTP, auth, Bolt, APOC, edition).
- `movies_dataset.py` - CRUD operations (create, verify, cleanup the Movies graph).
- `azure_helpers.py` - Azure SDK operations (get VM status, get disk status, restart VM).
- `wait.py` - readiness polling (HTTP endpoint, with timeout and interval).
- `reporting.py` - test context manager, result tracking, summary table output.
- `resilience.py` - persistence test orchestration (sentinel write, restart, verify, cleanup).

### Error Handling

- Connectivity and CRUD failures are reported but do not abort the suite; all tests run to completion so the full picture is visible.
- Resilience tests abort early if the sentinel write or dataset creation fails, since subsequent verification would be meaningless.
- Cleanup operations (sentinel deletion, Movies deletion) are best-effort and never mask test results.

## Implementation Status

All modules are implemented, reviewed against Azure SDK best practices, and the project builds successfully.

| Module | Status | Description |
|--------|--------|-------------|
| `pyproject.toml` | Done | uv project config, hatchling build, CLI entry point |
| `.python-version` | Done | Pinned to 3.12 |
| `src/test_ce/config.py` | Done | Frozen `StackConfig` dataclass, `load_from_scenario()`, `load_from_args()`, uses `azure.mgmt.core.tools.parse_resource_id` for subscription extraction |
| `src/test_ce/reporting.py` | Done | `TestResult` dataclass, `TestContext` with safe default message, `TestReporter` with context manager and summary table |
| `src/test_ce/wait.py` | Done | `wait_for_neo4j()` HTTP polling with timeout, clamped remaining-time display |
| `src/test_ce/neo4j_checks.py` | Done | 5 connectivity tests with empty-result-set guards: HTTP API, HTTP auth, Bolt, APOC, Community edition |
| `src/test_ce/movies_dataset.py` | Done | Pure functions (`create_movies`, `verify_movies`, `cleanup_movies`) with no reporter dependency for reuse in resilience |
| `src/test_ce/azure_helpers.py` | Done | Single `DefaultAzureCredential` reused across calls, `ComputeManagementClient` as context manager, `parse_resource_id` for resource ID parsing, LRO timeout on `poller.result()`, immutable `tuple` for `DiskStatus.zones` |
| `src/test_ce/resilience.py` | Done | 6-phase cycle: sentinel write, movies create, VM restart, recovery wait, post-restart verification, cleanup |
| `src/test_ce/cli.py` | Done | argparse with mutually exclusive `--scenario`/`--uri`, shared `_run_crud_tests` helper, `--timeout` applied to both initial wait and post-restart recovery |

### Azure SDK Best Practices Applied

- **Credential reuse**: A single `DefaultAzureCredential()` instance is created at module level and shared across all `ComputeManagementClient` instances, avoiding redundant credential-chain discovery.
- **Client context managers**: `ComputeManagementClient` is used via `with` statement to properly close HTTP connections and avoid leaks.
- **Official resource ID parsing**: Uses `azure.mgmt.core.tools.parse_resource_id()` instead of manual string splitting, with validation of parsed components before SDK calls.
- **LRO timeout**: `poller.result(timeout=300)` on VM restart to prevent indefinite hangs.
- **Immutable data**: `DiskStatus.zones` uses `tuple[str, ...]` instead of `list[str]` for consistency with `frozen=True` dataclass.

### Usage

```
cd test_suite/test_ce

# Scenario mode (reads from deployments framework)
uv run test-ce --scenario standalone-ce-latest --simple

# Manual mode (explicit connection details, connectivity + CRUD only)
uv run test-ce --uri bolt://host:7687 --password MyPassword --simple

# Full mode with resilience (requires Azure context from scenario)
uv run test-ce --scenario standalone-ce-latest
```

## Verification

- Run the suite in `--simple` mode against a fresh CE deployment and confirm all connectivity and CRUD tests pass.
- Run the full suite and confirm the VM restart cycle completes, Neo4j recovers, and the sentinel and Movies data survive.
- Confirm the suite exits with code 1 when a test is intentionally broken (wrong password, unreachable endpoint).
- Confirm the summary table accurately reflects test outcomes and durations.
