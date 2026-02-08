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

## NVMe disk controller

The CE template uses `diskControllerType: 'NVMe'` with the Ebdsv5 VM series (`Standard_E4bds_v5`), departing from the SCSI disk controller pattern used in the enterprise template.

NVMe delivers higher remote disk throughput (21,400 IOPS / 600 MBps) compared to SCSI (16,200 IOPS / 350 MBps) at the same price. NVMe is Microsoft's forward direction — newer VM generations (v6+) are NVMe-only.

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

### Why NVMe over SCSI

The Ebdsv5 VM series delivers higher remote disk throughput via NVMe (21,400 IOPS / 600 MBps) compared to SCSI (16,200 IOPS / 350 MBps) at the same price. NVMe is Microsoft's forward direction — newer VM generations (v6+) are NVMe-only. RHEL 9 supports NVMe natively but requires the [azure-vm-utils](https://github.com/Azure/azure-vm-utils) udev rules for `/dev/disk/azure/data/by-lun/` symlinks, which the cloud-init installs in `bootcmd`.

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

## Module structure

```
marketplace/neo4j-ce/
  main.bicep              # Orchestrator: pickZones() detection, cloud-init substitution
  modules/
    network.bicep         # VNet, subnet, NSG (unchanged)
    disk.bicep            # Standalone managed data disk (PremiumV2_LRS or Premium_LRS, conditional zone)
    vm.bicep              # VM (NVMe, conditional zone), NIC, public IP (conditional zone)
  scripts/neo4j-ce/
    cloud-init/
      standalone.yaml     # Cloud-init: NVMe udev rules, disk mount, Neo4j install, configuration
```
