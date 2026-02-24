# Neo4j CE Azure Architecture

Key design decisions for the Community Edition Azure deployment.

## Standalone VM instead of VMSS

The CE deployment uses a single `Microsoft.Compute/virtualMachines` resource instead of a Virtual Machine Scale Set. VMSS is designed for horizontally-scaled stateless workloads. The CE deployment runs exactly one node — every VMSS feature (capacity management, upgrade policies, overprovisioning, fault domain distribution) was either disabled or hardcoded to trivial values. A standalone VM eliminates this abstraction overhead and enables standard `az vm` commands for debugging.

Azure's service healing automatically restarts standalone VMs on healthy hosts when the underlying hardware fails. This provides the same single-instance availability guarantee that VMSS offered, without the indirection.

## Standalone managed data disk

> **Never put database data on the OS disk.** If you delete the VM and lose the OS disk, you lose the data from the database. A separate managed disk survives VM deletion, so a replacement VM reattaches it and picks up where the last one left off. For production deployments, this is the difference between a routine redeployment and total data loss.

Although Azure managed disks replicate data three times within a datacenter (LRS), and host failures are handled transparently by migrating the VM to healthy hardware, that hardware redundancy doesn't protect against VM lifecycle events. The OS disk is tied to the VM resource. When the VM is deleted, whether by a failed redeployment, a scale-down, or an operator mistake, the OS disk is deleted with it and those three replicas disappear together. A separate data disk with `deleteOption: Detach` has the same three-replica hardware protection, but its lifecycle is independent of the VM. Delete the VM and the data disk stays.

Every database platform on the Azure Marketplace puts its data files on a separate managed disk. SQL Server, MongoDB, Cassandra, PostgreSQL all follow the same pattern. The [Azure Well-Architected Framework for Disk Storage](https://learn.microsoft.com/azure/well-architected/service-guides/azure-disk-storage#performance-efficiency) recommends Premium SSD or better for database workloads, with `deleteOption: Detach` to decouple disk lifecycle from VM lifecycle. The cost is identical for a single-node deployment since Azure charges for storage capacity regardless of how disks are organized.

The Neo4j data disk is defined as a separate `Microsoft.Compute/disks` resource (`disk.bicep`), not as an inline data disk on the VM profile.

**The value of external disks:**

- **Data survives VM deletion.** The disk persists independently of the VM lifecycle. When the VM is deleted, whether intentionally or by Azure during host recovery, the disk stays. A new VM attaches it via `createOption: Attach` and resumes with all data intact.
- **Independent sizing.** Data disk capacity is chosen separately from the OS disk. Pay only for the storage you need.
- **I/O isolation.** Database reads and writes don't compete with OS operations for disk bandwidth.

**How it works:**

1. `disk.bicep` creates an empty Premium_LRS managed disk sized by the `diskSize` parameter (32-4095 GB)
2. `vm.bicep` attaches it at LUN 0 with `deleteOption: 'Detach'`
3. Cloud-init formats the disk (XFS) and mounts it at `/var/lib/neo4j` using Azure udev symlinks (`/dev/disk/azure/data/by-lun/0`)

`deleteOption: Detach` on the VM's data disk attachment tells Azure to detach (not delete) the disk when the VM resource is removed.

**Redeployment:** ARM incremental mode is idempotent. If the disk already exists with matching properties, ARM skips recreation. The VM is created fresh and attaches the existing disk.

**Durability:** Azure managed disks with Premium_LRS store 3 replicas within a single datacenter. The disk is resilient to VM crashes, reboots, deallocation, deletion (detached, not deleted), and host hardware failure (Azure migrates the VM; the disk is unaffected). It is not resilient to datacenter-wide outages (LRS has no geo-redundancy) or deletion of the disk resource itself.

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

## No zone pinning — Premium_LRS everywhere

The template deploys all resources without availability zone pinning and uses `Premium_LRS` for all disks. This was a deliberate decision after testing revealed a fundamental flaw with the previous `pickZones()` approach (see "Why zone pinning was removed" below).

This means:
- **Data disk** (`disk.bicep`): `Premium_LRS`, no `zones` property
- **Public IP** (`vm.bicep`): no `zones` property
- **VM** (`vm.bicep`): no `zones` property

The trade-off is losing `PremiumV2_LRS`'s tuneable IOPS/throughput, but for a marketplace template that must work with every VM size in every region, universal compatibility is the right call. The disk storage tier (`Premium_LRS` vs `PremiumV2_LRS`) is independent of the disk controller type (NVMe vs SCSI) — switching to `Premium_LRS` does not affect NVMe/SCSI compatibility.

## Trusted Launch security

All VMs use the `TrustedLaunch` security profile with Secure Boot and vTPM enabled. This is required by the marketplace image definition (`SecurityType=TrustedLaunch`).

```bicep
securityProfile: {
  securityType: 'TrustedLaunch'
  uefiSettings: {
    secureBootEnabled: true
    vTpmEnabled: true
  }
}
```

The image definition uses `SecurityType=TrustedLaunch` (not `TrustedLaunchSupported`), which means VMs from this image can **only** be Trusted Launch. `TrustedLaunchSupported` would allow both Gen2 and Trusted Launch, but the stricter setting is acceptable since the Bicep template always sets Trusted Launch.

## Image selection (3-way)

The VM supports three image sources, selected by priority:

1. **Gallery image** (`galleryImageId` parameter) — for pre-publish testing of new image versions
2. **Test image** (`useTestImage=true`) — deploys from a standard RHEL 9 image for CI testing
3. **Marketplace image** (default) — the published `neo4j-ce-vm` marketplace offer

Gallery and test images skip the marketplace `plan` block. The marketplace image includes it.

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

- **Public IP:** Standard SKU, static allocation. The DNS label `neo4j-{suffix}` produces a hostname like `neo4j-abc123.eastus2.cloudapp.azure.com`.
- **NIC:** References the subnet from the existing `network.bicep` module and the public IP. Accelerated networking (`enableAcceleratedNetworking: true`) is enabled for SR-IOV hardware offload.

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

## Design decisions and lessons learned

### Why zone pinning was removed

The template originally used `pickZones('Microsoft.Compute', 'virtualMachines', location)` to auto-detect zone support and pin resources to zone 1 with `PremiumV2_LRS` disks.

Testing revealed a fundamental flaw: `pickZones()` checks whether a **resource type** supports zones in a region, but it does **not** consider the specific **VM SKU**. In `northeurope`, `Standard_E2ds_v6` is only available in zones 2 and 3 — but `pickZones()` returns `['1']`, so the template pinned the VM to zone 1 where the SKU doesn't exist, producing an `OverconstrainedZonalAllocationRequest` error.

```
$ az vm list-skus --location northeurope --size Standard_E2ds_v6 \
    --query "[].{name:name, zones:locationInfo[0].zones}"
[{ "name": "Standard_E2ds_v6", "zones": ["2", "3"] }]
```

This is not just a testing problem — it affects marketplace customers too. Any customer selecting a v6 VM in a region where that SKU isn't in zone 1 would hit this error. The `createUiDefinition.json` recommends `Standard_E4ds_v6` as the default, making this a likely failure path.

Three options were evaluated:
- **Option A: Remove zone pinning** — simplest and safest, works everywhere
- **Option B: Explicit zone parameter** — correct by design, but requires the customer to know which zone their VM size supports
- **Option C: Query SKU availability at deploy time** — adds complexity and a deployment script dependency

Option A was chosen. `Premium_LRS` works in every region with every VM size. NVMe (v6) and SCSI (v5) VMs both work with `Premium_LRS` disks. This matches how the Enterprise template works (no zone pinning).

### Why passwords must avoid shell metacharacters

Testing uncovered a silent authentication failure when the generated password contained shell-hostile characters like `$`, backticks, or `^`. The password flow is:

1. Deploy tool generates password, base64-encodes it in the Bicep parameter
2. `main.bicep` base64-encodes again for cloud-init: `base64(adminPassword)`
3. Cloud-init decodes and passes to bash: `neo4j-admin dbms set-initial-password "$ADMIN_PASSWORD"`

The base64 encoding protects the password during YAML transport, but after `base64 -d` decodes it, characters like `$^` are interpreted as variable expansion by bash (even inside double quotes). The password gets silently truncated, causing Neo4j to set a different password than the one the customer expects.

**Fixes applied:**
- Password generator (`deployments/src/password.py`): restricted special characters to shell-safe set: `! @ # % _ + - = .`
- Marketplace UI (`createUiDefinition.json`): PasswordBox regex only accepts those same safe characters, with a validation message telling the user which characters are allowed

### Marketplace image build requirements

Building a gallery image that works across both NVMe (v6) and SCSI (v5) VMs requires careful attention to the source VM configuration:

1. **Source VM must use a v6+ size with NVMe.** The gallery image version inherits the disk controller type from the source VM's VHD, not from the image definition features. An image definition declaring `DiskControllerTypes=SCSI,NVMe` is necessary but **not sufficient** — the VHD itself must be NVMe-compatible. The source VM (`Standard_D2ds_v6`) must be created with `--disk-controller-type NVMe`.

2. **Trusted Launch images require explicit security profile.** Gallery images with `SecurityType=TrustedLaunch` require deploying VMs to set `securityProfile` with `securityType: 'TrustedLaunch'`. Azure does not auto-infer this from the image.

3. **Accelerated networking must be explicitly enabled.** The image definition declares `IsAcceleratedNetworkSupported=True`, but Azure does not auto-enable it on the NIC. The `enableAcceleratedNetworking: true` property must be set explicitly on the NIC resource.

4. **Gallery images must be replicated to deployment regions.** Image versions are only available in the regions they have been replicated to. Use `--target-regions` during `az sig image-version create` to replicate at capture time.

### Why Eds_v6 (NVMe-only)

The Eds_v6 series uses 5th Gen Intel Xeon (Emerald Rapids) processors and is NVMe-only — all v6+ VM generations dropped SCSI support. NVMe delivers higher remote disk throughput compared to SCSI at the same price. Using an NVMe-only series eliminates the ambiguity of dual-capable SKUs (where Azure defaults to SCSI when `diskControllerType` is omitted). Neo4j Aura already runs E-Series v6 in production on Azure. The template omits `diskControllerType` — for NVMe-only SKUs, Azure automatically uses NVMe without explicit configuration.

### Why unconditional password setting

The enterprise template sets `neo4j-admin dbms set-initial-password` unconditionally. The CE template originally added a conditional check (`if [ ! -d /var/lib/neo4j/data/dbms ]`) intended to preserve credentials on reattached disks, but this check fails on fresh deployments because the Neo4j RPM creates that directory during package installation onto the already-mounted data disk. The fix removes the conditional. `set-initial-password` is safe to always call — it only works before the first start and exits harmlessly if auth is already configured.

### Resources

- [DBMS deployment guidance for SAP workloads — storage structure](https://learn.microsoft.com/azure/sap/workloads/dbms-guide-general#storage-structure-of-a-vm-for-rdbms-deployments)
- [SQL Server on Azure VMs — storage best practices](https://learn.microsoft.com/azure/azure-sql/virtual-machines/windows/performance-guidelines-best-practices-storage)
- [Edsv6 VM series — NVMe and disk performance](https://learn.microsoft.com/en-us/azure/virtual-machines/edsv6-series)
- [Premium SSD v2 — regional availability and constraints](https://learn.microsoft.com/en-us/azure/virtual-machines/disks-types#premium-ssd-v2)
- [Azure NVMe disk identification — azure-vm-utils](https://learn.microsoft.com/en-us/azure/virtual-machines/linux/azure-virtual-machine-utilities)
- [Azure disk device naming and symlinks](https://learn.microsoft.com/en-us/troubleshoot/azure/virtual-machines/linux/troubleshoot-device-names-problems)
- [NVMe FAQ: How to create image definition supporting NVMe](https://learn.microsoft.com/azure/virtual-machines/enable-nvme-remote-faqs#how-do-i-create-an-image-definition-that-supports-nvme-for-remote-disks)
- [NVMe Overview: Supported VM families](https://learn.microsoft.com/azure/virtual-machines/nvme-overview)
- [Neo4j Operations Manual — set-initial-password](https://neo4j.com/docs/operations-manual/current/configuration/set-initial-password/)
- [Neo4j Operations Manual — file locations (RPM)](https://neo4j.com/docs/operations-manual/5/configuration/file-locations/)
- [Azure pickZones() function reference](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/bicep-functions-resource#pickzones)
- [Products available by region](https://azure.microsoft.com/en-us/explore/global-infrastructure/products-by-region/)

## Module structure

```
marketplace/neo4j-ce/
  main.bicep              # Orchestrator: cloud-init substitution, module wiring
  modules/
    network.bicep         # VNet, subnet, NSG
    disk.bicep            # Standalone managed data disk (Premium_LRS)
    vm.bicep              # VM (NVMe via Eds_v6, Trusted Launch), NIC (accelerated networking), public IP
scripts/neo4j-ce/
  cloud-init/
    standalone.yaml       # Cloud-init: NVMe udev rules, disk mount, Neo4j install, configuration
```
