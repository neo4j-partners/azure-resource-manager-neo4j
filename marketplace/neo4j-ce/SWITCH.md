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

### main.bicep

Add two derived variables (no new parameters):

- `zones`: the result of `pickZones('Microsoft.Compute', 'virtualMachines', location)`
- `useZones`: `!empty(zones)` — a boolean derived from the pickZones result

Pass `useZones` to both the `disk` and `vm` modules.

### modules/disk.bicep

Add one parameter: `useZones` (bool).

Two conditional changes:

- `zones`: set to `['1']` when useZones is true, omit (null) when false
- `sku.name`: set to `PremiumV2_LRS` when useZones is true, `Premium_LRS` when false

### modules/vm.bicep

Add one parameter: `useZones` (bool).

Two conditional changes on two resources:

- Public IP `zones`: set to `['1']` when useZones is true, omit when false
- VM `zones`: set to `['1']` when useZones is true, omit when false

No changes to diskControllerType, NVMe config, network module, or cloud-init.

### parameters.json and scenarios.yaml

No changes needed. Zone detection is fully automatic.

### createUiDefinition.json

No changes needed. The template handles all regions. A description note about the Premium SSD v2 / Premium SSD fallback is optional.

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
