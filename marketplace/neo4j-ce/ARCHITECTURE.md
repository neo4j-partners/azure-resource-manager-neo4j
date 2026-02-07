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

## PremiumV2_LRS with Zone 1 pinning

The data disk uses `PremiumV2_LRS` (Premium SSD v2) pinned to availability zone 1. Both the disk and the VM must be in the same zone — Azure requires this for Premium SSD v2 in AZ-enabled regions.

PremiumV2_LRS was chosen over Premium_LRS because:
- Better baseline IOPS (3000) and throughput (125 MB/s) at no additional cost
- Sub-millisecond latency
- Available in 41 regions including all major deployment targets (East US, East US 2, West Europe, etc.)

Zone 1 is hardcoded rather than parameterized. CE is a single-node deployment where zone selection is arbitrary. Adding a zone parameter would increase complexity for no practical benefit.

## Cloud-init idempotency for disk reattach

The cloud-init configuration (`scripts/neo4j-ce/cloud-init/standalone.yaml`) handles both fresh disks and reattached disks with existing data:

**Disk formatting:**
- `disk_setup` uses `overwrite: false` — skips partitioning if a partition table already exists
- `fs_setup` uses `overwrite: false` — skips filesystem creation if an XFS filesystem is already present
- `mounts` is unconditional — mounts the partition at `/var/lib/neo4j` regardless of whether it was just formatted or already contains data

**Password setup:**
- `neo4j-admin dbms set-initial-password` is a one-time command. It fails with "live Neo4j users were detected" if the auth directory already exists.
- The cloud-init script checks for `/var/lib/neo4j/data/dbms` before running `set-initial-password`. On a reattached disk, this directory exists and the password step is skipped, preserving the original credentials.

## No managed identity

The identity module was removed. The previous deployment created a `UserAssigned` managed identity but nothing consumed it — no role assignments, no Azure API calls from cloud-init. Removing it eliminates an unused billable resource and reduces deployment time.

## Networking: standalone public IP and NIC

The VM uses discrete `Microsoft.Network/publicIPAddresses` and `Microsoft.Network/networkInterfaces` resources instead of VMSS-inline network configuration.

- **Public IP:** Standard SKU, static allocation, zone-aligned to zone 1. The DNS label `neo4j-{suffix}` produces a hostname like `neo4j-abc123.eastus2.cloudapp.azure.com`.
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

## Module structure

```
marketplace/neo4j-ce/
  main.bicep              # Orchestrator: wires modules, cloud-init substitution
  modules/
    network.bicep         # VNet, subnet, NSG (unchanged)
    disk.bicep            # Standalone managed data disk (PremiumV2_LRS, Zone 1)
    vm.bicep              # VM, NIC, public IP
  scripts/neo4j-ce/
    cloud-init/
      standalone.yaml     # Cloud-init: disk mount, Neo4j install, configuration
```
