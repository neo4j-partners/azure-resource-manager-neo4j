# Image Testing Status

## Run 1 (pre zone-fix)

| Scenario | Status | Notes |
|---|---|---|
| ce-eastus2-nvme | PASSED | NVMe, US |
| ce-uksouth-nvme | PASSED | NVMe, Europe |
| ce-swedencentral-scsi | PASSED | SCSI, Europe |
| ce-northcentralus-scsi | PASSED | SCSI, US |
| ce-ukwest-scsi | PASSED | SCSI, Europe |
| ce-northeurope-nvme | **FAILED** | `OverconstrainedZonalAllocationRequest` — see investigation below |

## Run 2 (post zone-fix, pre password-fix)

| Scenario | Status | Notes |
|---|---|---|
| ce-eastus2-nvme | PASSED | NVMe, US |
| ce-uksouth-nvme | PASSED | NVMe, Europe |
| ce-swedencentral-scsi | **FAILED** | `Unauthorized` — password with shell-hostile chars, see investigation below |
| ce-northcentralus-scsi | PASSED | SCSI, US |
| ce-ukwest-scsi | PASSED | SCSI, Europe |
| ce-northeurope-nvme | PASSED | NVMe, Europe — zone fix confirmed |

## Investigation: `ce-northeurope-nvme` Failure

### Error

```
OverconstrainedZonalAllocationRequest: Allocation failed. VM(s) with the
following constraints cannot be allocated, because the condition is too
restrictive. Please remove some constraints and try again. Constraints applied are:
  - Availability Zone
  - Networking Constraints (such as Accelerated Networking or IPv6)
  - VM Size
```

### Root Cause

The CE template uses `pickZones('Microsoft.Compute', 'virtualMachines', location)` to detect zone support. Per [Microsoft docs](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/bicep-functions-resource#pickzones), this function:

- Returns `['1']` for any zonal region (default `numberOfZones=1`, `offset=0`)
- **Does NOT consider the specific VM SKU** — it only checks if the resource type supports zones in that region

In `northeurope`, `Standard_E2ds_v6` (and all Eds_v6 sizes) are only available in **zones 2 and 3**:

```
$ az vm list-skus --location northeurope --size Standard_E2ds_v6 \
    --query "[].{name:name, zones:locationInfo[0].zones}"
[{ "name": "Standard_E2ds_v6", "zones": ["2", "3"] }]
```

But `pickZones` returns `['1']`, so the template pins the VM, disk, and public IP to zone 1 — where the SKU doesn't exist.

**This is not just a testing problem — it affects marketplace customers too.** Any customer selecting a v6 VM in `northeurope` (or any region where v6 isn't in zone 1) will hit this error.

### Impact on Marketplace Customers

The `createUiDefinition.json` recommends `Standard_E4ds_v6` as the default VM size. If a customer deploys in `northeurope`, the deployment fails immediately. The allowed VM size list includes both v5 and v6 sizes, and zone availability varies by region and SKU family.

### Fix Options

**Option A: Remove zone pinning, use Premium_LRS everywhere**

Remove the `pickZones` logic entirely. Deploy all resources without zone pinning and use `Premium_LRS` for all disks.

- Simplest, safest — works in every region with every VM size
- Loses PremiumV2_LRS disk performance in zonal regions
- Matches how the EE template works (no zone pinning)

```bicep
// Remove: var zones = pickZones(...)
// Remove: var useZones = !empty(zones)
// Disk: always Premium_LRS, no zones property
// VM/PublicIP: no zones property
```

**Option B: Add an explicit `availabilityZone` parameter**

Follow the [Azure Verified Modules pattern](https://azure.github.io/Azure-Verified-Modules/specs/bcp/res/interfaces/#zonal--zone-redundant-resources): add a parameter that lets the user choose a zone (or opt out).

```bicep
@allowed([-1, 1, 2, 3])
@description('Availability zone. Set to -1 to deploy without zone pinning.')
param availabilityZone int = -1
```

- Customer picks the zone (or -1 for no zone) in `createUiDefinition.json`
- Requires the customer to know which zone their VM size supports
- More complex UI, but correct by design

**Option C: Keep `pickZones` but fall back gracefully**

Use `pickZones` with `numberOfZones=3` to get all available zones, then let ARM pick. But a single VM must be pinned to exactly one zone — ARM doesn't auto-select.

- Doesn't solve the fundamental mismatch between `pickZones` (region-level) and SKU availability (zone-level)
- Would need a deployment script or other mechanism to query `az vm list-skus` at deploy time — adds complexity and a dependency

### Decision: Option A

**Go with Option A — remove zone pinning, use `Premium_LRS` everywhere.**

Key insight: the disk storage tier (`Premium_LRS` vs `PremiumV2_LRS`) is completely independent of the disk controller type (NVMe vs SCSI). The disk controller is determined by the VM size family (v6 = NVMe, v5 = SCSI), not by the disk SKU. So switching to `Premium_LRS` does not affect NVMe/SCSI compatibility at all.

- `Premium_LRS` works in every region, with every VM size, with or without zones
- NVMe (v6) and SCSI (v5) VMs both work with `Premium_LRS` disks
- No zone pinning means no `OverconstrainedZonalAllocationRequest` errors
- The trade-off is losing `PremiumV2_LRS`'s tunable IOPS/throughput, but for a marketplace template that needs universal compatibility, this is the right call

---

## Investigation: `ce-swedencentral-scsi` Auth Failure

### Error

```
Neo.ClientError.Security.Unauthorized: The client is unauthorized due to authentication failure.
```

### Root Cause

The generated password contained shell-hostile characters: `-#lc&X(}SqmIwj$^d3b[zDj<`

The password flow is:
1. Deploy tool generates password, base64-encodes it in the Bicep parameter
2. `main.bicep` base64-encodes again for cloud-init: `var passwordBase64 = base64(adminPassword)`
3. Cloud-init decodes and passes to bash: `neo4j-admin dbms set-initial-password "$ADMIN_PASSWORD"`

The base64 encoding protects during YAML transport, but after `base64 -d` decodes the password, characters like `$^` are interpreted as variable expansion by bash (even inside double quotes). The `$^d3b` substring becomes empty, so `neo4j-admin` sets a truncated password that doesn't match what the validator sends.

**This affects marketplace customers too.** Any customer typing `$`, backticks, or other shell metacharacters in their password would hit the same silent auth failure.

### Fix

1. **Password generator** (`deployments/src/password.py`): Restricted special character alphabet to shell-safe characters: `! @ # % _ + - = .`
2. **Marketplace UI** (`createUiDefinition.json`): Updated the PasswordBox regex to only accept those same safe special characters, with a validation message telling the user which characters are allowed.

---


# Neo4j CE Marketplace Image v1.1.0 — Test Plan

Test matrix for validating the published `neo4j-ce-vm` marketplace image (v1.1.0) across disk controller types, zone configurations, and regions.

## Background

The v1.1.0 image was built with NVMe + SCSI support (`DiskControllerTypes=SCSI,NVMe`) and TrustedLaunch security. It is now published to the Azure Marketplace. This test plan validates that the **marketplace image** (not the test RHEL 9 image) deploys correctly across all supported configurations.

All scenarios use `useTestImage=false` (the default) to exercise the published marketplace image.

## Test Dimensions

| Dimension | Values | Notes |
|---|---|---|
| **Disk Controller** | NVMe (v6 VMs), SCSI (v5 VMs) | Determined by VM size family |
| **Region** | US + Europe mix | Validates geo availability |
| **Neo4j Version** | `latest` (CalVer), `5` (LTS) | Cloud-init installs via `dnf` |

All scenarios use `Premium_LRS` disks with no zone pinning (post zone-fix).

## Scenarios

### 1. `ce-eastus2-nvme` — NVMe (US baseline)

| Field | Value |
|---|---|
| **Region** | `eastus2` |
| **VM Size** | `Standard_E4ds_v6` (NVMe) |
| **Disk** | Premium_LRS, 32 GB |
| **Neo4j Version** | `latest` |
| **Purpose** | Baseline: recommended VM size in default US region |

### 2. `ce-uksouth-nvme` — NVMe (Europe)

| Field | Value |
|---|---|
| **Region** | `uksouth` |
| **VM Size** | `Standard_E4ds_v6` (NVMe) |
| **Disk** | Premium_LRS, 32 GB |
| **Neo4j Version** | `latest` |
| **Purpose** | NVMe in a European region |

### 3. `ce-swedencentral-scsi` — SCSI (Europe, LTS)

| Field | Value |
|---|---|
| **Region** | `swedencentral` |
| **VM Size** | `Standard_E4s_v5` (SCSI) |
| **Disk** | Premium_LRS, 32 GB |
| **Neo4j Version** | `5` |
| **Purpose** | SCSI (v5) in Europe + LTS version |

### 4. `ce-northcentralus-scsi` — SCSI (US)

| Field | Value |
|---|---|
| **Region** | `northcentralus` |
| **VM Size** | `Standard_E4s_v5` (SCSI) |
| **Disk** | Premium_LRS, 32 GB |
| **Neo4j Version** | `latest` |
| **Purpose** | SCSI in US region |

### 5. `ce-ukwest-scsi` — SCSI (Europe, LTS)

| Field | Value |
|---|---|
| **Region** | `ukwest` |
| **VM Size** | `Standard_E4s_v5` (SCSI) |
| **Disk** | Premium_LRS, 32 GB |
| **Neo4j Version** | `5` |
| **Purpose** | SCSI in Europe + LTS version |

### 6. `ce-northeurope-nvme` — NVMe smaller size (Europe, LTS)

| Field | Value |
|---|---|
| **Region** | `northeurope` |
| **VM Size** | `Standard_E2ds_v6` (NVMe) |
| **Disk** | Premium_LRS, 32 GB |
| **Neo4j Version** | `5` |
| **Purpose** | Smaller v6 VM size + LTS in Europe (previously failed with zone pinning) |

## Coverage Matrix

| Scenario | Controller | Region | Neo4j |
|---|---|---|---|
| `ce-eastus2-nvme` | NVMe (v6) | US | latest |
| `ce-uksouth-nvme` | NVMe (v6) | Europe | latest |
| `ce-swedencentral-scsi` | SCSI (v5) | Europe | 5 |
| `ce-northcentralus-scsi` | SCSI (v5) | US | latest |
| `ce-ukwest-scsi` | SCSI (v5) | Europe | 5 |
| `ce-northeurope-nvme` | NVMe (v6) | Europe | 5 |

**Totals:** 3 NVMe + 3 SCSI, 2 US + 4 Europe, 3 latest + 3 LTS. All use Premium_LRS.

## Scenario Definitions

Add to `deployments/src/setup.py` (replacing the existing 3 CE scenarios):

```python
# CE marketplace image validation (v1.1.0)
TestScenario(
    name="ce-eastus2-nvme",
    deployment_type=DeploymentType.VM,
    node_count=1,
    graph_database_version="latest",
    vm_size="Standard_E4ds_v6",
    disk_size=32,
    license_type="Community",
    region="eastus2",
),
TestScenario(
    name="ce-uksouth-nvme",
    deployment_type=DeploymentType.VM,
    node_count=1,
    graph_database_version="latest",
    vm_size="Standard_E4ds_v6",
    disk_size=32,
    license_type="Community",
    region="uksouth",
),
TestScenario(
    name="ce-swedencentral-scsi",
    deployment_type=DeploymentType.VM,
    node_count=1,
    graph_database_version="5",
    vm_size="Standard_E4s_v5",
    disk_size=32,
    license_type="Community",
    region="swedencentral",
),
TestScenario(
    name="ce-northcentralus-scsi",
    deployment_type=DeploymentType.VM,
    node_count=1,
    graph_database_version="latest",
    vm_size="Standard_E4s_v5",
    disk_size=32,
    license_type="Community",
    region="northcentralus",
),
TestScenario(
    name="ce-ukwest-scsi",
    deployment_type=DeploymentType.VM,
    node_count=1,
    graph_database_version="5",
    vm_size="Standard_E4s_v5",
    disk_size=32,
    license_type="Community",
    region="ukwest",
),
TestScenario(
    name="ce-northeurope-nvme",
    deployment_type=DeploymentType.VM,
    node_count=1,
    graph_database_version="5",
    vm_size="Standard_E2ds_v6",
    disk_size=32,
    license_type="Community",
    region="northeurope",
),
```

## Running the Tests

```bash
# 1. Update scenarios (re-run setup or edit scenarios.yaml)
cd deployments
uv run neo4j-deploy setup

# 2. Validate Bicep compiles
uv run neo4j-deploy validate

# 3. Deploy all CE scenarios (they run in parallel)
uv run neo4j-deploy deploy -s ce-eastus2-nvme
uv run neo4j-deploy deploy -s ce-uksouth-nvme
uv run neo4j-deploy deploy -s ce-swedencentral-scsi
uv run neo4j-deploy deploy -s ce-northcentralus-scsi
uv run neo4j-deploy deploy -s ce-ukwest-scsi
uv run neo4j-deploy deploy -s ce-northeurope-nvme

# 4. Monitor deployment status
uv run neo4j-deploy status

# 5. Run validation tests (after deployments complete)
uv run neo4j-deploy test

# 6. Clean up all resources
uv run neo4j-deploy cleanup --all
```

## Validation Checks

Each scenario runs the full `Neo4jValidator` suite:

1. **Edition check** — `CALL dbms.components()` returns `community`
2. **CRUD test** — Create Movies dataset, verify nodes, clean up
3. **Bolt connectivity** — `bolt://<public-ip>:7687` reachable
4. **Cloud-init success** — Neo4j installed and started by `dnf install -y neo4j`

## Pass/Fail Criteria

| Check | Pass | Fail |
|---|---|---|
| ARM deployment | Succeeds within 30 min | Deployment error or timeout |
| Bolt connection | Responds on port 7687 | Connection refused or timeout |
| Edition | `community` | `enterprise` or error |
| Movies CRUD | Creates and reads nodes | Write or read failure |
| Disk type | Premium_LRS | Wrong SKU or deployment error |

## Known Considerations

- **Quota limits**: v6 VMs may require quota requests in some subscriptions/regions. If a deployment fails with quota errors, request quota for `Standard_Edsv6` family in that region.
- **Marketplace image propagation**: After publishing v1.1.0 in Partner Center, it may take up to 24 hours for the image to be available in all regions. If a deployment fails with "image not found", wait and retry.
- **TrustedLaunch**: All VMs use TrustedLaunch security profile (secureBootEnabled + vTpmEnabled). This is required by the image definition.
- **No zone pinning**: The template deploys all resources without availability zone pinning and uses `Premium_LRS` disks everywhere. This ensures compatibility with all VM SKUs in all regions.
