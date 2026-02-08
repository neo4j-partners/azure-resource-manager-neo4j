# Proposal: Automatic Zonal Deployment for Neo4j CE Template

## Problem Statement

The CE template hardcodes `zones: ['1']` on three resources (VM, public IP, data disk) and uses `PremiumV2_LRS` for the data disk. PremiumV2_LRS requires zonal VMs in regions that support availability zones. This combination works in most major regions, but will fail outright in regions that have no availability zones at all, such as North Central US and West US.

Since this is a marketplace template, customers choose the region at deploy time. A customer selecting a non-zonal region gets a deployment failure with no workaround.

## Can the Template Detect This Automatically?

Yes. Bicep has a built-in function called `pickZones()` that queries Azure Resource Manager at deploy time to determine whether a resource type supports availability zones in the target region:

```
pickZones('Microsoft.Compute', 'virtualMachines', location)
```

- In a zonal region (e.g., East US 2): returns `['1']`
- In a non-zonal region (e.g., North Central US): returns `[]` (empty array)

This runs during template evaluation, not at authoring time. No hardcoded region lists, no customer input needed. The template detects the region's capabilities and adapts.

The disk SKU decision can be derived from the same check: if `pickZones` returns zones, use PremiumV2_LRS; if it returns empty, fall back to Premium_LRS. One function call drives all three conditional decisions (VM zones, public IP zones, disk zones, and disk SKU).

## Can the Marketplace UI Tell the Customer?

Partially. The `createUiDefinition.json` location selector supports a `resourceTypes` filter that restricts the region dropdown to regions where specific resource types exist. Setting `"resourceTypes": ["Microsoft.Compute/disks"]` filters to regions where disks are available. However, this is a coarse filter. It cannot distinguish between PremiumV2_LRS and Premium_LRS availability within a region.

The `ArmApiControl` element in `createUiDefinition.json` can make live ARM API calls (like querying `Microsoft.Compute/resourceSkus`) and use the results to populate dropdowns or add validation warnings. This could technically query PremiumV2_LRS availability per region, but the implementation is complex, fragile, and hard to debug. It adds significant maintenance burden for a minor UX improvement.

Since the template auto-detects via `pickZones()` and falls back gracefully, the marketplace UI does not need to filter regions. The customer picks any region and the template does the right thing. A note in the description field ("Premium SSD v2 is used in regions with availability zone support; Premium SSD is used elsewhere") is sufficient.

## Regional Availability Research

### Standard_E4bds_v5 (NVMe VM)

Available in 70 regions. Every major US, Europe, and Asia region has it. Zone 1 is present in all regions that have zones.

Regions with 3 availability zones (all include zone 1):

| US | Europe | Asia-Pacific |
|---|---|---|
| East US | North Europe | Japan East |
| East US 2 | UK South | Southeast Asia |
| Central US | France Central | Australia East |
| West US 3 | Germany West Central | Korea Central |
| Canada Central | Sweden Central | Central India |
| Brazil South | Switzerland North | East Asia |
| | Norway East | Indonesia Central |
| | Italy North | |
| | Spain Central | |
| | Poland Central | |
| | Austria East | |

Regions where E4bds_v5 exists but has no zones (deployment will auto-detect and skip zonal pinning):

- North Central US
- West US
- Australia Southeast
- Canada East
- Japan West
- UK West
- Norway West
- South India

Regions where E4bds_v5 exists with zones but is subscription-restricted (needs quota request):

- West Europe
- South Central US
- West US 2

### PremiumV2_LRS (Premium SSD v2)

Available in 51 regions. Present in every major US, Europe, and Asia region. The overlap with E4bds_v5 zonal regions is near-complete. Key constraints:

- Must attach to a zonal VM in AZ-enabled regions
- Cannot be used as an OS disk (template already uses Premium_LRS for OS disk)
- Does not support host caching (template already sets caching to None)
- Same pricing model as Premium SSD but with tuneable IOPS/throughput

Regions where PremiumV2_LRS exists but has no zones:

- North Central US
- West US
- Australia Central 2
- Australia Southeast
- Canada East
- Norway West
- UK West
- West Central US

In non-zonal regions, PremiumV2_LRS can technically be used with availability sets, but this adds complexity for little benefit. Falling back to Premium_LRS in these regions is simpler and sufficient.

### Zone 1 Availability

Every Azure region that has availability zones includes zone 1. The numbering always starts at 1, though the physical datacenter mapped to "zone 1" is randomized per subscription. Pinning to zone 1 is safe in any zonal region.

### Combined Compatibility Matrix

When all three requirements are combined (E4bds_v5 + PremiumV2_LRS + zone 1), the template works in at least 25 major regions across all continents. In the remaining non-zonal regions, the template automatically falls back to non-zonal + Premium_LRS. No region is excluded from deployment.

## Proposed Solution

Use `pickZones()` at deploy time to detect zone support, then derive all zone and disk SKU decisions from that single check. No customer-facing parameters, no hardcoded region lists, no marketplace UI changes.

The logic:

1. Call `pickZones('Microsoft.Compute', 'virtualMachines', location)` in main.bicep
2. If the result is non-empty, the region supports zones: pin all resources to zone 1, use PremiumV2_LRS
3. If the result is empty, the region does not support zones: skip zone pinning on all resources, use Premium_LRS

This is a small change. Three resources have zone pinning (public IP, VM, data disk). One resource has the disk SKU (data disk). All are already in separate modules with clean parameter passing.

## What Changes

### main.bicep — DONE

Added two derived variables (no new parameters):

- `zones`: the result of `pickZones('Microsoft.Compute', 'virtualMachines', location)` (line 46)
- `useZones`: `!empty(zones)` — a boolean derived from the pickZones result (line 47)

Passed `useZones` to both the `disk` module (line 63) and `vm` module (line 96).

### modules/disk.bicep — DONE

Added one parameter: `useZones` (bool) (line 11).

Two conditional changes:

- `zones`: `useZones ? ['1'] : null` (line 18)
- `sku.name`: `useZones ? 'PremiumV2_LRS' : 'Premium_LRS'` (line 20)

### modules/vm.bicep — DONE

Added one parameter: `useZones` (bool) (line 33).

Two conditional changes on two resources:

- Public IP `zones`: `useZones ? ['1'] : null` (line 42)
- VM `zones`: `useZones ? ['1'] : null` (line 79)

No changes to diskControllerType, NVMe config, network module, or cloud-init.

### parameters.json and scenarios.yaml — No changes needed

Zone detection is fully automatic.

### createUiDefinition.json — No changes needed

The template handles all regions. A description note about the Premium SSD v2 / Premium SSD fallback is optional.

### Bicep compilation — PASSED

Compiles with only pre-existing BCP081 warnings (forward API versions) and one cosmetic BCP321 warning on the public IP `zones` property type (`'1'[] | null` vs `string[]`). This is expected when using a nullable ternary and does not affect deployment.

## Reliability Assessment

### Is pickZones a best practice?

Yes. Microsoft's own [Azure Landing Zones (ALZ) Bicep templates](https://azure.github.io/Azure-Landing-Zones/bicep/gettingstarted/) use `pickZones()` to automatically determine availability zones per region. These are production-grade templates backed by Microsoft support and used as the recommended starting point for enterprise Azure deployments. The ALZ documentation states: "The Bicep templates automatically determine the best availability zones for each resource type and region. This logic uses `pickZones()` in the `main.bicep` files."

The [Azure Verified Modules (AVM)](https://azure.github.io/Azure-Verified-Modules/) specification — Microsoft's official standard for IaC modules — takes a complementary approach: modules accept a `zones` parameter with sensible defaults, and consumers use `pickZones()` to pass the right values. Both patterns rely on the same underlying ARM capability.

### Known issues and mitigations

1. **Management group scoped deployments** ([GitHub #5462](https://github.com/Azure/bicep/issues/5462)): `pickZones()` can return `InternalServerError` when called from a module that is invoked at management group scope. This does not affect our template — marketplace deployments run at resource group scope, which is the standard and tested path.

2. **Indexing into empty results**: `pickZones(...)[0]` will fail with an out-of-bounds error if the region has no zones. The proposed implementation avoids this entirely by using `!empty(zones)` to derive a boolean, then using ternary expressions (`useZones ? ['1'] : null`). No array indexing is needed.

3. **Zone-redundant services (ZRS)**: `pickZones()` returns an empty array for ZRS resource types. This does not apply — we are querying `Microsoft.Compute/virtualMachines`, which is a zonal resource type and returns zone numbers correctly.

4. **VS Code tooling**: The VS Code ARM Tools extension may show false syntax errors for `pickZones()`. This is a cosmetic IDE issue, not a runtime problem. Bicep CLI compiles and deploys correctly.

### What about the Azure Selected Zone feature?

[Azure Selected Zone](https://github.com/Azure/AzureSelectedZone) (`zonePlacementPolicy='any'`) is a preview feature that lets Azure auto-select the optimal zone. It is currently limited to East US 2 EUAP, is not GA, and has unknown interaction with PremiumV2_LRS. It is not suitable for a marketplace template that must work broadly today.

### Bottom line

`pickZones()` is a built-in ARM function that runs server-side during template evaluation. It does not add external dependencies, deployment scripts, managed identities, or network calls. It has been available since API version 2022-08-01 and is used in Microsoft's own production landing zone templates. The only known bug (management group scope) does not affect marketplace deployments. The proposed usage pattern (boolean derivation, no array indexing) avoids all documented edge cases.

## Complexity Assessment

Low. Two new variables in main.bicep, one new parameter threaded to two modules, five conditional expressions. No new files, no new abstractions, no customer-facing parameters.

The `pickZones()` function is a built-in Bicep function that runs during ARM template evaluation. It requires no managed identity, no deployment scripts, and no external dependencies. It has been available since ARM API version 2022-08-01.

Cross-resource dependency: the data disk and VM must be in the same zone for attachment to succeed. Since both reference the same `useZones` variable derived from a single `pickZones()` call, they will always agree. The network module (VNet, NSG) has no zone properties and needs no changes.

## Tradeoffs

In non-zonal regions (automatic fallback):

- No availability zone protection (single-datacenter failure risk)
- Premium_LRS instead of PremiumV2_LRS (lower baseline IOPS: 7,500 vs tuneable up to 80,000; higher latency; no independent IOPS/throughput scaling)
- Still uses NVMe disk controller and E4bds_v5 VM (no performance regression on the compute side)

In zonal regions (the default path for all major regions):

- Full availability zone protection
- PremiumV2_LRS with sub-millisecond latency and tuneable performance
- Covers all major US, Europe, and Asia-Pacific regions

## Requirements

1. The template must deploy successfully in any region where Standard_E4bds_v5 is available, regardless of zone support.
2. In zonal regions, the template must deploy all resources to zone 1 with PremiumV2_LRS.
3. In non-zonal regions, the template must deploy all resources without zone pinning, using Premium_LRS for the data disk.
4. The data disk and VM must always be in the same zone (or both non-zonal). No mixed configuration.
5. Zone detection must be automatic. No customer-facing parameter, no hardcoded region list.
6. No new modules, no compatibility layers, no migration phases.

## Design Decisions and Resources

### Why pickZones() is reliable for this template

1. **Microsoft uses it in production.** The [Azure Landing Zones (ALZ) Bicep templates](https://azure.github.io/Azure-Landing-Zones/bicep/gettingstarted/) — Microsoft's own recommended enterprise deployment baseline — use `pickZones()` in their `main.bicep` files to auto-detect zone support. These templates are backed by Microsoft support and are the default path for production Azure deployments.

2. **The only known bug doesn't apply.** The one documented issue ([GitHub #5462](https://github.com/Azure/bicep/issues/5462)) is an `InternalServerError` when `pickZones()` is called from a module invoked at management group scope. Marketplace deployments run at resource group scope — the standard, well-tested path.

3. **The proposed usage pattern avoids all edge cases.** The common pitfall is indexing into an empty array (`pickZones(...)[0]`). The proposed implementation instead uses `!empty(pickZones(...))` to derive a boolean, then ternary expressions. No array indexing, no loops over the result.

`pickZones()` is a server-side ARM function — no deployment scripts, no managed identities, no external dependencies. Available since API version 2022-08-01.

### Why NVMe over SCSI

The CE template intentionally moves away from the SCSI disk controller pattern used in the enterprise template. The Ebdsv5 VM series delivers higher remote disk throughput via NVMe (21,400 IOPS / 600 MBps) compared to SCSI (16,200 IOPS / 350 MBps) at the same price. NVMe is Microsoft's forward direction — newer VM generations (v6+) are NVMe-only. RHEL 9 supports NVMe natively but requires the [azure-vm-utils](https://github.com/Azure/azure-vm-utils) udev rules for `/dev/disk/azure/data/by-lun/` symlinks, which the cloud-init installs in `bootcmd`.

### Why PremiumV2_LRS with Premium_LRS fallback

Premium SSD v2 provides sub-millisecond latency and tuneable IOPS/throughput independent of disk size — important for database workloads where a 32GB disk would otherwise be limited to 120 IOPS on Premium SSD. The fallback to Premium_LRS in non-zonal regions ensures the template deploys everywhere the VM SKU is available, at the cost of reduced IOPS in those secondary regions.

### Why unconditional password setting

The enterprise template sets `neo4j-admin dbms set-initial-password` unconditionally. The CE template originally added a conditional check (`if [ ! -d /var/lib/neo4j/data/dbms ]`) intended to preserve credentials on reattached disks, but this check fails on fresh deployments because the Neo4j RPM creates that directory during package installation onto the already-mounted data disk. The fix removes the conditional. `set-initial-password` is safe to always call — it only works before the first start and exits harmlessly if auth is already configured.

### Resources

- [Azure pickZones() function reference](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/bicep-functions-resource#pickzones)
- [Azure Landing Zones Bicep — zone auto-detection](https://azure.github.io/Azure-Landing-Zones/bicep/gettingstarted/)
- [Azure Verified Modules (AVM) — zone interface spec](https://azure.github.io/Azure-Verified-Modules/specs/bcp/res/interfaces/)
- [Ebdsv5 VM series — NVMe and disk performance](https://learn.microsoft.com/en-us/azure/virtual-machines/ebdsv5-ebsv5-series)
- [Premium SSD v2 — regional availability and constraints](https://learn.microsoft.com/en-us/azure/virtual-machines/disks-types#premium-ssd-v2)
- [Azure NVMe disk identification — azure-vm-utils](https://learn.microsoft.com/en-us/azure/virtual-machines/linux/azure-virtual-machine-utilities)
- [Azure disk device naming and symlinks](https://learn.microsoft.com/en-us/troubleshoot/azure/virtual-machines/linux/troubleshoot-device-names-problems)
- [Neo4j Operations Manual — set-initial-password](https://neo4j.com/docs/operations-manual/current/configuration/set-initial-password/)
- [Neo4j Operations Manual — file locations (RPM)](https://neo4j.com/docs/operations-manual/5/configuration/file-locations/)
- [pickZones management group scope bug — GitHub #5462](https://github.com/Azure/bicep/issues/5462)
- [Zone-aware ARM/Bicep patterns — nimccoll/ZoneAware](https://github.com/nimccoll/ZoneAware)
