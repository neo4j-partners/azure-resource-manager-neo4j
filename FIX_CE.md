# Neo4j Community Edition - Fixes and Implementation Plan

## What CE Is

Neo4j Community Edition on Azure is a single-node deployment for developers, small projects, and evaluation use. It should be simple to deploy, reliable on first boot, and not over-engineered. There is no clustering, no multi-node, no high availability. One VM, one disk, one Neo4j instance.

---

## Decisions: What We Are NOT Doing (and Why)

### No Load Balancer

A load balancer in front of a single VM adds cost and complexity for zero benefit. CE users connect directly to the VM's public IP via the DNS label. This is fine.

### No Multi-Zone Spread

Spreading instances across multiple zones only helps if you have multiple nodes. With a single node there is nothing to spread. We do pin the VM to a single zone (zone 1) because Premium SSD v2 requires it, but this is not a high-availability strategy -- it is just a one-line requirement to unlock better storage.

### No Static/Elastic IP

Azure VMSS does not natively support static public IPs per instance. The CE template already uses a DNS label (e.g., vm0.neo4j-abc123.eastus.cloudapp.azure.com) which is stable across reboots and deallocations. This is sufficient for CE. A static IP would require a separate public IP resource and more wiring for no real gain.

---

## What Happens If the VM Dies

This is worth understanding for CE users:

- **VM reboot or reimage**: The managed data disk (where Neo4j data lives) survives. Data is preserved. Neo4j comes back up with all its data intact.
- **VM instance deleted from the VMSS**: The data disk is deleted with it because it is defined in the VMSS model. Data is lost. This is the expected behavior for a VMSS-managed disk.
- **The VMSS itself is deleted (resource group cleanup)**: Everything is gone.

For CE, this is acceptable. CE is not designed for production workloads that need data durability guarantees beyond basic VM restarts. Users who need that should use Enterprise Edition with clustering and backups.

---

## Fixes That Actually Matter

The following changes address real problems: VMs that fail to deploy, cloud-init scripts that break on newer hardware, and missing guardrails that let users shoot themselves in the foot.

### Fix 1: Upgrade to Premium SSD v2 with Zonal Deployment

**The problem**: The template currently uses Premium SSD (Premium_LRS). Premium SSD v2 offers better price-per-IOPS, a free baseline of 3,000 IOPS and 125 MB/s, and the ability to tune IOPS and throughput independently without resizing the disk. It is the recommended storage tier for database workloads on Azure.

**Why we avoided this before**: Premium SSD v2 requires zonal VM deployment. We initially thought this added architectural complexity. It does not. For a single-node deployment, it is just pinning the VM to zone 1 -- one property on the VMSS resource and one property to set the fault domain count to 1. No load balancer changes, no multi-zone logic, no availability set concerns.

**The fix**: Two small changes in the VMSS module. First, add `zones: ['1']` and `platformFaultDomainCount: 1` to the VMSS resource so it deploys into a specific zone. Second, change the data disk `storageAccountType` from `Premium_LRS` to `PremiumV2_LRS`. The caching is already set to `None`, which is what Premium SSD v2 requires.

**Region availability**: Premium SSD v2 is available in 50+ regions including all major ones (East US, West US 2, West Europe, Southeast Asia, etc.). There are a handful of smaller regions where it is not available. If a user tries to deploy in an unsupported region, Azure will reject the deployment with a clear error before any resources are created.

**Where**: `marketplace/neo4j-ce/modules/vmss.bicep` -- add zones and platformFaultDomainCount, change storageAccountType.

### Fix 2: Universal Disk Path for NVMe Support

**The problem**: The cloud-init script uses `/dev/disk/azure/scsi1/lun0` to find the data disk. This path only exists on VMs with SCSI disk controllers. Newer Azure VMs (v6-series, FX-series) use NVMe controllers, where this path does not exist. Deploying CE on one of these VMs will fail silently -- the data disk never gets mounted, and Neo4j either fails to start or writes to the OS disk.

**The fix**: Change the disk path to `/dev/disk/azure/data/by-lun/0`. This is a universal symlink that Azure creates regardless of whether the disk controller is SCSI or NVMe. It works on all current and future VM families. There is no reason to drop SCSI support -- the universal path handles both controller types with zero extra complexity. Users who pick a v5 VM get SCSI, users who pick a v6 VM get NVMe, and the same cloud-init config works for both.

**Where**: `scripts/neo4j-ce/cloud-init/standalone.yaml` -- three places: disk_setup, fs_setup, and mounts sections.

### Fix 3: VM Size Allowlist

**The problem**: The UI currently only blocks two VM sizes (Standard_B1s and Standard_B1ls). This means users can select ARM64 VMs (which will not work because the image is x64-only), GPU VMs (unnecessary cost), burstable VMs (inconsistent performance), or tiny VMs that do not have enough memory to run Neo4j.

**The fix**: Switch from `excludedSizes` to `allowedSizes` in the marketplace UI definition. Curate a list of VM sizes that are known to work well with Neo4j CE. Focus on E-series (memory-optimized, best for Neo4j), D-series (general purpose, widely available), and a few others. Start smaller than the Enterprise list since CE users typically run smaller workloads.

Suggested VM families for CE:
- D-series v4 (general purpose, 4 to 64 vCPUs) -- still heavily used in production, widest availability and quota across Azure regions
- E-series v5 (memory-optimized, 4 to 64 vCPUs) -- best fit for Neo4j
- D-series v5 (general purpose, 4 to 64 vCPUs) -- good alternative, most common generation in use today
- E-series v6 and D-series v6 -- newer generation, NVMe-capable, limited availability for now

Including v4 is important because Azure has availability issues in most regions and many subscriptions still have quota for v4 but not v5 or v6. Aura's own production fleet runs 410 D-series v4 instances alongside 531 v5 instances. Dropping v4 would lock out a significant number of users.

Skip L-series (storage-optimized, overkill for CE) and FX-series (compute-optimized, niche) to keep the list manageable. These are more appropriate for Enterprise.

Also update the recommended sizes to put the most common CE choices first.

**Where**: `marketplace/neo4j-ce/createUiDefinition.json` -- the vmSize constraints section.

### Fix 4: Password Validation at Template Level

**The problem**: The marketplace UI validates password complexity (12-72 characters, 3 of 4 character types). But if someone deploys via the ARM API or CLI directly, they bypass the UI and can pass in a 1-character password. Neo4j requires at least 8 characters.

**The fix**: Add `@minLength(8)` and `@maxLength(72)` decorators to the adminPassword parameter in main.bicep. This ensures the ARM API itself rejects bad passwords before the deployment even starts.

**Where**: `marketplace/neo4j-ce/main.bicep` -- the adminPassword parameter.

### Fix 5: Package Install Retry Logic

**The problem**: The cloud-init script runs `rpm --import` and `dnf install` once each with no retries. If there is a transient network issue, a DNS hiccup, or if the package manager is locked by an unattended update running at boot, the install fails and Neo4j never gets installed. The user sees a VM that deployed "successfully" but Neo4j is not running.

**The fix**: Add retry logic around the GPG key import and the dnf install command. Also add a wait loop at the start that checks for package manager locks before proceeding. Five attempts with 10-second delays between them is sufficient for transient failures.

**Where**: `scripts/neo4j-ce/cloud-init/standalone.yaml` -- the runcmd section.

### Fix 6: Memory Validation

**The problem**: If someone bypasses the UI allowlist (via CLI or API) and deploys on a VM with less than 4 GB of RAM, Neo4j will either fail to start or run so poorly it is unusable. The error is not obvious from cloud-init logs.

**The fix**: Add a memory check at the start of the runcmd section. If the VM has less than 3500 MB of available memory, exit with a clear error message. This provides defense in depth behind the VM allowlist.

**Where**: `scripts/neo4j-ce/cloud-init/standalone.yaml` -- beginning of runcmd section.

### Fix 7: Readiness Check Timeout

**The problem**: The cloud-init script waits for Neo4j to respond on port 7474 with an infinite loop. If Neo4j fails to start for any reason, the cloud-init process hangs forever. The VM appears to be provisioning indefinitely.

**The fix**: Add a timeout to the readiness loop. If Neo4j has not responded after 5 minutes (300 seconds), exit with an error. This gives operators a clear signal that something went wrong instead of leaving them guessing.

**Where**: `scripts/neo4j-ce/cloud-init/standalone.yaml` -- the readiness check at the end of runcmd.

---

## Implementation Order

These are listed in the order they should be done. Fixes 1 and 2 go together since they both affect storage and should be tested as a pair. The rest are independent.

1. **Premium SSD v2 + zonal deployment** -- unlocks better storage, small template change
2. **Universal disk path** -- must accompany the storage change to support both SCSI and NVMe VMs
3. **VM size allowlist** -- prevents the most common user mistakes
4. **Package install retries** -- improves first-boot reliability
5. **Readiness check timeout** -- prevents hung deployments
6. **Memory validation** -- defense in depth
7. **Password validation** -- defense in depth

---

## Testing

After all fixes are applied:

1. Deploy CE with a Standard_E4s_v5 (SCSI controller) -- verify Neo4j starts, data disk mounts, and Premium SSD v2 is used
2. Deploy CE with a Standard_E4s_v6 (NVMe controller) -- verify the universal disk path works with Premium SSD v2
3. Deploy CE with a Standard_D4s_v5 -- verify a general purpose VM works
4. Verify the disk is Premium SSD v2 by checking the disk SKU in the Azure portal or via CLI
5. Attempt deployment via CLI with a short password -- verify it is rejected
6. Check cloud-init logs for retry and memory validation messages
7. Verify the marketplace UI only shows allowed VM sizes
8. Try deploying in a region without Premium SSD v2 support -- verify Azure rejects it with a clear error

---

## Files to Change

| File | What Changes |
|------|-------------|
| `marketplace/neo4j-ce/modules/vmss.bicep` | Add zones, platformFaultDomainCount, change to PremiumV2_LRS |
| `scripts/neo4j-ce/cloud-init/standalone.yaml` | Disk path, retries, memory check, readiness timeout |
| `marketplace/neo4j-ce/createUiDefinition.json` | VM size allowlist and recommended sizes |
| `marketplace/neo4j-ce/main.bicep` | Password length validation decorators |
