# Proposal: Data Resiliency for Neo4j CE on Azure

## Open Questions

These must be resolved before implementation begins.

### 1. DNS label changes on VM replacement

The current VMSS assigns a DNS label per-instance with the pattern `vm{NODE_INDEX}.neo4j-{suffix}`. A standalone VM uses a standalone public IP resource with a single DNS label (no `vm0.` prefix). This changes the public hostname from `vm0.neo4j-XXXX.eastus2.cloudapp.azure.com` to `neo4j-XXXX.eastus2.cloudapp.azure.com`. That is a breaking change for the `Neo4jBrowserURL` output and for any clients using the old hostname. Is this acceptable, or should the DNS label be set to `vm0.neo4j-{suffix}` to preserve the existing hostname format?


**ANSWER**: This change is acceptable because there are no legacy clients that need to be supported.

### 2. PremiumV2_LRS zone and feature constraints

The current VMSS uses `PremiumV2_LRS` for the data disk and pins to Zone 1. `PremiumV2_LRS` requires zone assignment and is not available in all regions. A standalone `Microsoft.Compute/disks` resource with `PremiumV2_LRS` must also be pinned to a zone, and the VM must be in the same zone. Two sub-questions:

- Should the template keep `PremiumV2_LRS` (better IOPS/throughput, zone-required, limited region availability) or switch to `Premium_LRS` (widely available, no zone requirement, sufficient for most CE workloads) to match the enterprise template?
- If keeping `PremiumV2_LRS`, should the zone be parameterized or stay hardcoded to `1`?

**ANSWER**: How limiting are the available regions for PremiumV2_LRS?  What do the azure docs recommend for zone paraemter?

### 3. Disk lifecycle on resource group deletion

The proposal says the managed disk should survive VM deletion. It will, because the disk is a separate resource and deleting a VM does not cascade to attached managed disks unless `deleteOption: Delete` is set. However, `az group delete` deletes everything in the group, including the standalone disk. The proposal's Phase 3 mentions this but is vague ("should be retainable or documented"). What is the actual expectation? Options:

- Accept that `az group delete` destroys everything (standard Azure behavior) and just document it.
- Add a resource lock (`Microsoft.Authorization/locks`) on the disk to prevent accidental deletion (requires explicit lock removal before group delete).
- No action needed beyond documentation.

**ANSWER**: The goal is to support the instance dying unexpectedly so that it can survive restarts.  If the user deletes it with az group delete then that's fine, just document that.  The goal is a minimal level of resiliency. 

### 4. Cloud-init behavior on reattach with existing data

The cloud-init config uses `overwrite: false` on `disk_setup`, which correctly skips partitioning if a partition table exists. But `fs_setup` does not have an explicit `overwrite: false` — cloud-init's default behavior is to skip formatting if a filesystem already exists, but this is implicit. Additionally, Neo4j's `set-initial-password` command will fail on a reattached disk where the password was already set (the auth file already exists in `/var/lib/neo4j/data`). Should the cloud-init script:

- Skip `set-initial-password` if `/var/lib/neo4j/data/dbms/auth` already exists?
- Add explicit `overwrite: false` to `fs_setup` for clarity?

**ANSWER**:  What does neo4j operation manual and azure docs recommend

### 5. CI workflow VMSS references

The community CI workflow (`community.yml`) references VMSS-specific outputs and commands: `vmScaleSetsName`, `az vmss list-instances`, `az vmss run-command invoke`. These must all be updated. Should the CI workflow changes be included in this PR, or handled separately?

**ANSWER**:  fix everything following best practices

### 6. Identity module — is it still needed?

The managed identity (`identity.bicep`) is created but never used for anything — there are no role assignments, and the CE cloud-init does not call any Azure APIs that require identity-based auth. The VMSS attaches it via `UserAssigned` identity, but nothing consumes it. Should the identity module be removed entirely for CE to reduce resource count, or kept for future use?

**ANSWER**:  fix everything following best practices


### 7. Redeployment workflow

The proposal says "for deliberate redeployment, `az vm create` against the same resource group reattaches the persisted data disk." But the Bicep template creates the VM and disk together. If the VM is deleted outside of ARM (e.g., via portal or CLI), rerunning the Bicep deployment will try to create a new disk, which will conflict with the existing one (same name). What is the expected redeployment workflow?

- Delete VM only (via CLI), then redeploy the full template (ARM detects the existing disk and skips creation)?
- Use `az vm create` manually (outside of Bicep)?
- Something else?

ARM incremental mode will not delete the existing disk when the VM is removed, but it needs to handle the case where the disk already exists on redeployment. Bicep's `existing` keyword or a conditional `if` on the disk resource may be needed.

**ANSWER**: The goal is to support the instance dying unexpectedly so that it can survive restarts.   The goal is a minimal level of resiliency.  What is the best way of supporting that? 

### 8. Marketplace impact

The CE template has a `createUiDefinition.json` and `makeArchive.sh` for marketplace publishing. Does this change need to be coordinated with a marketplace re-submission? Are there any marketplace certification constraints that affect the choice between VMSS and standalone VM?

**ANSWER**: This is a new marketplace deployment and those should be updated to reflect the latest changes to CE templates

## Problem Statement

The Azure CE deployment loses all Neo4j data when a VM instance is replaced. The data disk is defined inline within a Virtual Machine Scale Set (VMSS) profile, so Azure deletes the managed disk whenever the VMSS instance is deleted or reimaged. There is no mechanism to preserve the data volume independently of the VM lifecycle.

The AWS CE deployment solved this problem by defining the EBS data volume as a standalone CloudFormation resource with `DeletionPolicy: Retain`. When the Auto Scaling Group replaces a failed instance, the new instance reattaches the surviving volume and resumes with all data intact. The Azure deployment has no equivalent.

A secondary problem is architectural complexity. VMSS is Azure's horizontal scaling primitive, designed to manage pools of identical VMs behind a load balancer. The CE deployment runs exactly one instance with `capacity: 1`. Using VMSS for a single-node database adds indirection (scale set instance IDs, upgrade policies, fault domain configuration, VMSS-specific networking) without providing any benefit. A standalone VM is simpler to deploy, debug, and operate.

## Proposed Solution

Replace the VMSS-based deployment with a standalone Azure VM and a separately managed data disk. The managed disk resource will exist independently in the resource group, surviving VM deletion. Cloud-init will detect and mount the existing disk on subsequent boots without reformatting, preserving all Neo4j data across VM replacements.

This brings the Azure deployment to parity with the AWS CE architecture while reducing template complexity.

## Requirements

1. The Neo4j data disk must be defined as a standalone `Microsoft.Compute/disks` Bicep resource, not as an inline data disk on the VM profile.
2. The standalone disk must persist when the VM is deleted or redeployed. Deleting the VM must not delete the data disk.
3. A new VM must be able to attach the existing data disk and mount it without formatting, preserving all prior Neo4j data.
4. The VMSS resource must be replaced with a single `Microsoft.Compute/virtualMachines` resource.
5. Cloud-init must detect whether the data disk already contains a filesystem and skip formatting if one exists.
6. All existing functionality (networking, identity, security rules, Neo4j configuration) must be preserved.
7. The public DNS label and Neo4j Browser URL output must continue to work.

## Why VMSS Is Wrong for This Deployment

VMSS (Virtual Machine Scale Set) is Azure's service for managing groups of identical, auto-scaling VMs. It is the Azure analog of AWS Auto Scaling Groups. VMSS is designed for stateless workloads that scale horizontally: web servers, API tiers, batch workers.

Using VMSS for a single Neo4j CE instance creates several problems:

**Data disks are ephemeral.** VMSS defines data disks in the VM profile, meaning the disk lifecycle is bound to the instance. When VMSS replaces an instance (reimage, scale-in, manual delete), the data disk is destroyed. There is no equivalent of `DeletionPolicy: Retain` for inline VMSS data disks.

**Operational complexity for no benefit.** VMSS introduces concepts that are meaningless for a single node: upgrade policies, overprovisioning, fault domain counts, scale set instance IDs, and capacity settings. Every one of these is either hardcoded to a trivial value (`capacity: 1`, `overprovision: false`, `platformFaultDomainCount: 1`) or set to a mode that disables the feature (`upgradePolicy: Manual`). This is configuration overhead with zero return.

**Debugging is harder.** VMSS instances are accessed through the scale set (e.g., `az vmss list-instances`, `az vmss get-instance-view`), not through standard VM commands. SSH requires knowing the instance ID within the scale set. Serial console, boot diagnostics, and disk management all route through VMSS-specific APIs. For a single node, this adds friction to every operational task.

**Networking is indirect.** VMSS defines network interfaces inside the VM profile with VMSS-specific IP configurations. A standalone VM uses a direct NIC and public IP, which are easier to inspect, modify, and troubleshoot.

**A standalone VM does everything VMSS does here.** The only argument for VMSS is automatic instance replacement on failure. A standalone VM with Azure's auto-restart policy provides the same guarantee for a single node, without the abstraction overhead. For deliberate redeployment, `az vm create` against the same resource group reattaches the persisted data disk.

## Implementation Plan

### Phase 1: Analysis

- [ ] Document the current VMSS networking configuration (NSG rules, public IP, DNS label) to ensure parity
- [ ] Document the current cloud-init disk setup and mount behavior
- [ ] Identify all references to VMSS outputs (`vmScaleSetsId`, `vmScaleSetsName`) in the main template and test code
- [ ] Review the identity module for any VMSS-specific role assignments

### Phase 2: Implementation

- [ ] Create a new `disk.bicep` module defining a standalone `Microsoft.Compute/disks` resource (PremiumV2_LRS, parameterized size, Zone 1)
- [ ] Replace `vmss.bicep` with `vm.bicep` containing a `Microsoft.Compute/virtualMachines` resource
- [ ] Attach the standalone managed disk to the VM via `dataDisks` with `createOption: Attach` and `managedDisk.id` referencing the disk resource
- [ ] Create a standalone `Microsoft.Network/publicIPAddresses` resource with the existing DNS label
- [ ] Create a standalone `Microsoft.Network/networkInterfaces` resource referencing the public IP and subnet
- [ ] Update cloud-init to detect existing filesystem on the data disk using `overwrite: false` (already present) and confirm mount idempotency
- [ ] Update `main.bicep` / `mainTemplate.json` to wire the new modules and update outputs
- [ ] Remove all VMSS-specific configuration (upgrade policy, fault domain count, overprovisioning, capacity, computer name prefix)

### Phase 3: Verification

- [ ] Deploy a fresh stack and confirm Neo4j starts with an empty data disk formatted and mounted at `/var/lib/neo4j`
- [ ] Write data to Neo4j, delete the VM, redeploy a new VM against the same resource group, and confirm all data is present
- [ ] Confirm the public DNS label resolves correctly after VM replacement
- [ ] Confirm the data disk survives full stack deletion (resource group delete should warn but disk should be retainable or documented)
- [ ] Run existing test suite and confirm no regressions
- [ ] Validate that `az vm` commands work directly without VMSS indirection
