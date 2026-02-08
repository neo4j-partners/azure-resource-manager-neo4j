# Neo4j CE Azure Architecture

Key design decisions for the Community Edition Azure deployment.

## Standalone VM instead of VMSS

The CE deployment uses a single `Microsoft.Compute/virtualMachines` resource instead of a Virtual Machine Scale Set. VMSS is designed for horizontally-scaled stateless workloads. The CE deployment runs exactly one node — every VMSS feature (capacity management, upgrade policies, overprovisioning, fault domain distribution) was either disabled or hardcoded to trivial values. A standalone VM eliminates this abstraction overhead and enables standard `az vm` commands for debugging.

Azure's service healing automatically restarts standalone VMs on healthy hosts when the underlying hardware fails. This provides the same single-instance availability guarantee that VMSS offered, without the indirection.

## Standalone managed data disk

The Neo4j data disk is defined as a separate `Microsoft.Compute/disks` resource (`disk.bicep`), not as an inline data disk on the VM profile.

**Why:** Inline VMSS data disks are destroyed when the instance is deleted or reimaged. A standalone disk resource persists independently of the VM lifecycle. When the VM is deleted (intentionally or by Azure during recovery), the disk survives. A new VM attaches the same disk via `createOption: Attach` and resumes with all data intact.

**deleteOption: Detach** is set on the VM's data disk attachment. This ensures Azure detaches (rather than deletes) the disk when the VM resource is removed.

**Redeployment:** ARM incremental mode is idempotent. If the disk already exists with matching properties, ARM skips recreation. The VM is created fresh and attaches the existing disk.

## NVMe disk controller (Eds_v6 series)

The CE template defaults to the Eds_v6 VM series (e.g., `Standard_E4ds_v6`), which is **NVMe-only**. No `diskControllerType` property is needed — v6 VMs exclusively use NVMe. This is Microsoft's forward direction; all v6+ VM generations dropped SCSI support entirely.

The template omits `diskControllerType` from the VM's `storageProfile`. For NVMe-only SKUs like Eds_v6, Azure automatically uses NVMe. If a user overrides `vmSize` to a v5 SKU that supports both NVMe and SCSI, Azure auto-selects based on the VM size's default. The [azure-vm-utils](https://github.com/Azure/azure-vm-utils) udev rules installed by cloud-init create `/dev/disk/azure/data/by-lun/` symlinks for both controllers, so the same disk paths work regardless.

### Recommended VM sizes

| Size | vCPUs | RAM | NVMe | Use case |
|------|-------|-----|------|----------|
| `Standard_E2ds_v6` | 2 | 16 GB | Yes (only) | Testing / evaluation |
| `Standard_E4ds_v6` | 4 | 32 GB | Yes (only) | Default |
| `Standard_E8ds_v6` | 8 | 64 GB | Yes (only) | Production workloads |

RHEL 9 supports NVMe natively but does not include the `/dev/disk/azure/data/by-lun/` symlinks by default. The cloud-init `bootcmd` installs [azure-vm-utils](https://github.com/Azure/azure-vm-utils) udev rules before `disk_setup` runs, creating the symlinks that cloud-init uses to format and mount the data disk at `/dev/disk/azure/data/by-lun/0`.

## Automatic zone detection with pickZones()

The template uses Bicep's built-in `pickZones()` function to detect availability zone support at deploy time:

```bicep
var zones = pickZones('Microsoft.Compute', 'virtualMachines', location)
var useZones = !empty(zones)
```

In zonal regions (East US 2, North Europe, etc.), `pickZones()` returns `['1']` and the template pins all resources to zone 1 with `PremiumV2_LRS`. In non-zonal regions (North Central US, West US, etc.), it returns `[]` and the template deploys without zone pinning using `Premium_LRS`.

This single check drives all conditional decisions across three resources:
- **Data disk** (`disk.bicep`): `zones` and `sku.name` (`PremiumV2_LRS` or `Premium_LRS`)
- **Public IP** (`vm.bicep`): `zones`
- **VM** (`vm.bicep`): `zones`

All three resources reference the same `useZones` boolean derived from `pickZones()`, ensuring the data disk and VM are always in the same zone (or both non-zonal). No customer-facing parameters, no hardcoded region lists.

PremiumV2_LRS was chosen for zonal regions because:
- Better baseline IOPS (3000) and throughput (125 MB/s) at no additional cost
- Sub-millisecond latency
- Tuneable IOPS/throughput independent of disk size (important for database workloads)
- Available in 51+ regions including all major deployment targets

In non-zonal regions, the fallback to Premium_LRS ensures the template deploys everywhere the VM SKU is available, at the cost of reduced IOPS in those secondary regions.

## Regional availability research

This section documents the regional availability of the three resources the template depends on: the VM SKU, the disk SKU, and availability zones. All data was verified against official Microsoft documentation and `az vm list-skus` in February 2026. Azure regions expand continuously — run `az vm list-skus --size Standard_E4ds_v6 --all --output table` for current per-subscription availability.

### Eds_v6 series (NVMe-only VM)

Microsoft does not publish a static region list for individual VM SKUs. The [Edsv6 series documentation](https://learn.microsoft.com/en-us/azure/virtual-machines/edsv6-series) directs users to the [Products available by region](https://azure.microsoft.com/en-us/explore/global-infrastructure/products-by-region/) tool or the Azure CLI (`az vm list-skus`). The Eds_v6 series is available across 40+ regions including all major US, Europe, and Asia-Pacific regions.

Key facts:
- Uses 5th Gen Intel Xeon Platinum (Emerald Rapids) processors
- NVMe-only — all v6 VMs dropped SCSI support
- Memory-optimized (8 GiB RAM per vCPU)
- Available in both zonal and non-zonal regions
- Some regions may require a quota request (check `az vm list-skus` for `NotAvailableForSubscription` restrictions)
- Not available in some smaller non-zonal regions (australiasoutheast, norwaywest, southindia)

### Availability zone support by region

Source: [Azure regions with availability zone support](https://learn.microsoft.com/en-us/azure/reliability/availability-zones-region-support) and [List of Azure regions](https://learn.microsoft.com/en-us/azure/reliability/regions-list).

Regions with availability zones (38 regions as of February 2026):

| US | Europe | Asia-Pacific | Other |
|---|---|---|---|
| East US | North Europe | Japan East | Brazil South |
| East US 2 | UK South | Southeast Asia | South Africa North |
| Central US | France Central | Australia East | Israel Central |
| West US 2 | Germany West Central | Korea Central | Qatar Central |
| West US 3 | Sweden Central | Central India | UAE North |
| South Central US | Switzerland North | East Asia | Mexico Central |
| | Norway East | Indonesia Central | Chile Central |
| | Italy North | Malaysia West | |
| | Spain Central | New Zealand North | |
| | Poland Central | South India | |
| | Austria East | Japan West | |
| | West Europe | Korea South | |
| | Belgium Central | | |
| | Denmark East | | |

Regions where the template auto-detects and deploys without zone pinning (non-zonal):

- North Central US
- West US
- Australia Southeast
- Australia Central / Central 2
- Canada East
- Norway West
- UK West
- West Central US
- West India
- France South, Germany North, Switzerland West, Sweden South, UAE Central, South Africa West (restricted access)

### PremiumV2_LRS (Premium SSD v2)

Source: [Premium SSD v2 — regional availability](https://learn.microsoft.com/en-us/azure/virtual-machines/disks-types#premium-ssd-v2).

Premium SSD v2 is available in 40+ regions. Key constraints:
- Must attach to a zonal VM in AZ-enabled regions
- Cannot be used as an OS disk (the template uses Premium_LRS for the OS disk)
- Does not support host caching (the template sets caching to None)
- Tuneable IOPS/throughput independent of disk size

**Regions with 2+ availability zones** (template uses PremiumV2_LRS + zone 1):

East US, East US 2, Central US, South Central US, West US 2, West US 3, Canada Central, Brazil South, North Europe, West Europe, UK South, France Central, Germany West Central, Sweden Central, Switzerland North, Norway East, Italy North, Spain Central, Poland Central, Austria East, Japan East, Southeast Asia, Australia East, Korea Central, Central India, East Asia, South Africa North, Israel Central, UAE North, Mexico Central

**Regions with 1 availability zone** (template uses PremiumV2_LRS + zone 1):

Indonesia Central, Japan West, New Zealand North, Malaysia West

**Regions without availability zones** (template falls back to Premium_LRS, no zone pinning):

North Central US, West US, Australia Southeast, Australia Central 2, Canada East, Norway West, UK West, West Central US, Taiwan North

### Zone 1 availability

Every Azure region that has availability zones includes zone 1. The logical zone numbers always start at 1, though the physical datacenter mapped to "zone 1" is randomized per subscription ([zone mapping](https://learn.microsoft.com/en-us/azure/reliability/availability-zones-overview#physical-and-logical-availability-zones)). Pinning to zone 1 via `pickZones('Microsoft.Compute', 'virtualMachines', location)` is safe in any zonal region.

### Combined compatibility

When all three requirements are combined (Eds_v6 + PremiumV2_LRS + zone support), the template deploys with full zonal + NVMe + PremiumV2_LRS configuration in 30+ major regions across all continents. In the remaining non-zonal regions where Eds_v6 is available (northcentralus, westus, canadaeast, ukwest), the template automatically falls back to non-zonal + Premium_LRS.

### Tradeoffs in non-zonal regions

- No availability zone protection (single-datacenter failure risk)
- Premium_LRS instead of PremiumV2_LRS (lower baseline IOPS: 7,500 vs tuneable up to 80,000; higher latency; no independent IOPS/throughput scaling)
- Still uses Eds_v6 VM with NVMe (no compute performance regression)

### How to verify for your subscription

```bash
# List Eds_v6 availability with zone and restriction info
az vm list-skus --size Standard_E4ds_v6 --all --output table

# Check zones for a specific region
az vm list-skus --size Standard_E4ds_v6 --location eastus2 --output table
```

## Cloud-init idempotency for disk reattach

The cloud-init configuration (`scripts/neo4j-ce/cloud-init/standalone.yaml`) handles both fresh disks and reattached disks with existing data:

**Disk formatting:**
- `disk_setup` uses `overwrite: false` — skips partitioning if a partition table already exists
- `fs_setup` uses `overwrite: false` — skips filesystem creation if an XFS filesystem is already present
- `mounts` is unconditional — mounts the partition at `/var/lib/neo4j` regardless of whether it was just formatted or already contains data

**Password setup:**
- `neo4j-admin dbms set-initial-password` runs unconditionally. It is a one-time command that only works before the first Neo4j start and exits harmlessly if auth is already configured.
- On a reattached disk with existing data, the command detects live users and exits with no effect, preserving the original credentials.

## No managed identity

The identity module was removed. The previous deployment created a `UserAssigned` managed identity but nothing consumed it — no role assignments, no Azure API calls from cloud-init. Removing it eliminates an unused billable resource and reduces deployment time.

## Networking: standalone public IP and NIC

The VM uses discrete `Microsoft.Network/publicIPAddresses` and `Microsoft.Network/networkInterfaces` resources instead of VMSS-inline network configuration.

- **Public IP:** Standard SKU, static allocation, zone-aligned when `useZones` is true (zone 1 in zonal regions, no zone pinning in non-zonal regions). The DNS label `neo4j-{suffix}` produces a hostname like `neo4j-abc123.eastus2.cloudapp.azure.com`.
- **NIC:** References the subnet from the existing `network.bicep` module and the public IP.

The network module (`network.bicep`) is unchanged. NSG rules (SSH/22, HTTPS/7473, HTTP/7474, Bolt/7687) and VNet/subnet configuration remain identical.

## DNS hostname change

The hostname changed from `vm0.neo4j-{suffix}.{region}.cloudapp.azure.com` (VMSS per-instance DNS) to `neo4j-{suffix}.{region}.cloudapp.azure.com` (standalone public IP DNS). The `vm0.` prefix was a VMSS artifact — VMSS prepends instance indices to DNS labels. A standalone public IP uses the DNS label directly.

## Template outputs

| Output | Description |
|--------|-------------|
| `neo4jBrowserURL` | HTTP URL to Neo4j Browser (port 7474) |
| `neo4jBoltURL` | Bolt protocol URL (port 7687) |
| `vmId` | Azure resource ID of the VM |
| `vmName` | Name of the VM resource |
| `dataDiskId` | Azure resource ID of the standalone data disk |
| `vnetId` | VNet resource ID |
| `subnetId` | Subnet resource ID |
| `nsgId` | NSG resource ID |
| `username` | Neo4j admin username (always `neo4j`) |

## Design decisions and resources

### Why pickZones() is reliable for this template

1. **Microsoft uses it in production.** The [Azure Landing Zones (ALZ) Bicep templates](https://azure.github.io/Azure-Landing-Zones/bicep/gettingstarted/) use `pickZones()` in their `main.bicep` files to auto-detect zone support. These are production-grade templates backed by Microsoft support.

2. **The only known bug doesn't apply.** The one documented issue ([GitHub #5462](https://github.com/Azure/bicep/issues/5462)) is an `InternalServerError` when `pickZones()` is called from a module invoked at management group scope. Marketplace deployments run at resource group scope.

3. **The usage pattern avoids all edge cases.** The common pitfall is indexing into an empty array (`pickZones(...)[0]`). The implementation uses `!empty(pickZones(...))` to derive a boolean, then ternary expressions. No array indexing.

`pickZones()` is a server-side ARM function — no deployment scripts, no managed identities, no external dependencies. Available since API version 2022-08-01.

Additional edge cases considered:

- **Zone-redundant services (ZRS):** `pickZones()` returns an empty array for ZRS resource types. This does not apply — we query `Microsoft.Compute/virtualMachines`, which is a zonal resource type and returns zone numbers correctly.
- **VS Code tooling:** The VS Code ARM Tools extension may show false syntax errors for `pickZones()`. This is a cosmetic IDE issue, not a runtime problem. Bicep CLI compiles and deploys correctly.
- **Azure Selected Zone:** [Azure Selected Zone](https://github.com/Azure/AzureSelectedZone) (`zonePlacementPolicy='any'`) is a preview feature that lets Azure auto-select the optimal zone. It is limited to East US 2 EUAP, is not GA, and has unknown interaction with PremiumV2_LRS. Not suitable for a marketplace template that must work broadly today.

### Why no marketplace UI region filtering

The `createUiDefinition.json` location selector supports a `resourceTypes` filter that restricts the region dropdown to regions where specific resource types exist. However, this is a coarse filter — it cannot distinguish between PremiumV2_LRS and Premium_LRS availability within a region. The `ArmApiControl` element can make live ARM API calls (like querying `Microsoft.Compute/resourceSkus`) to populate dropdowns or add validation warnings, but the implementation is complex, fragile, and hard to debug.

Since the template auto-detects via `pickZones()` and falls back gracefully, the marketplace UI does not need to filter regions. The customer picks any region and the template does the right thing.

### Why Eds_v6 (NVMe-only)

The Eds_v6 series uses 5th Gen Intel Xeon (Emerald Rapids) processors and is NVMe-only — all v6+ VM generations dropped SCSI support. NVMe delivers higher remote disk throughput compared to SCSI at the same price. Using an NVMe-only series eliminates the ambiguity of dual-capable SKUs (where Azure defaults to SCSI when `diskControllerType` is omitted). Neo4j Aura already runs E-Series v6 in production on Azure. The template omits `diskControllerType` — for NVMe-only SKUs, Azure automatically uses NVMe without explicit configuration.

### Why PremiumV2_LRS with Premium_LRS fallback

Premium SSD v2 provides sub-millisecond latency and tuneable IOPS/throughput independent of disk size — important for database workloads where a 32GB disk would otherwise be limited to 120 IOPS on Premium SSD. The fallback to Premium_LRS in non-zonal regions ensures the template deploys everywhere the VM SKU is available, at the cost of reduced IOPS in those secondary regions.

### Why unconditional password setting

The enterprise template sets `neo4j-admin dbms set-initial-password` unconditionally. The CE template originally added a conditional check (`if [ ! -d /var/lib/neo4j/data/dbms ]`) intended to preserve credentials on reattached disks, but this check fails on fresh deployments because the Neo4j RPM creates that directory during package installation onto the already-mounted data disk. The fix removes the conditional. `set-initial-password` is safe to always call — it only works before the first start and exits harmlessly if auth is already configured.

### Resources

- [Azure pickZones() function reference](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/bicep-functions-resource#pickzones)
- [Azure Landing Zones Bicep — zone auto-detection](https://azure.github.io/Azure-Landing-Zones/bicep/gettingstarted/)
- [Azure Verified Modules (AVM) — zone interface spec](https://azure.github.io/Azure-Verified-Modules/specs/bcp/res/interfaces/)
- [Edsv6 VM series — NVMe and disk performance](https://learn.microsoft.com/en-us/azure/virtual-machines/edsv6-series)
- [Premium SSD v2 — regional availability and constraints](https://learn.microsoft.com/en-us/azure/virtual-machines/disks-types#premium-ssd-v2)
- [Azure NVMe disk identification — azure-vm-utils](https://learn.microsoft.com/en-us/azure/virtual-machines/linux/azure-virtual-machine-utilities)
- [Azure disk device naming and symlinks](https://learn.microsoft.com/en-us/troubleshoot/azure/virtual-machines/linux/troubleshoot-device-names-problems)
- [Neo4j Operations Manual — set-initial-password](https://neo4j.com/docs/operations-manual/current/configuration/set-initial-password/)
- [Neo4j Operations Manual — file locations (RPM)](https://neo4j.com/docs/operations-manual/5/configuration/file-locations/)
- [pickZones management group scope bug — GitHub #5462](https://github.com/Azure/bicep/issues/5462)
- [Zone-aware ARM/Bicep patterns — nimccoll/ZoneAware](https://github.com/nimccoll/ZoneAware)
- [Azure regions with availability zone support](https://learn.microsoft.com/en-us/azure/reliability/availability-zones-region-support)
- [List of Azure regions](https://learn.microsoft.com/en-us/azure/reliability/regions-list)
- [Products available by region](https://azure.microsoft.com/en-us/explore/global-infrastructure/products-by-region/)
- [Availability zones — physical and logical zone mapping](https://learn.microsoft.com/en-us/azure/reliability/availability-zones-overview#physical-and-logical-availability-zones)

## Module structure

```
marketplace/neo4j-ce/
  main.bicep              # Orchestrator: pickZones() detection, cloud-init substitution
  modules/
    network.bicep         # VNet, subnet, NSG (unchanged)
    disk.bicep            # Standalone managed data disk (PremiumV2_LRS or Premium_LRS, conditional zone)
    vm.bicep              # VM (NVMe via Eds_v6, conditional zone), NIC, public IP (conditional zone)
  scripts/neo4j-ce/
    cloud-init/
      standalone.yaml     # Cloud-init: NVMe udev rules, disk mount, Neo4j install, configuration
```
