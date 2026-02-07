# Neo4j Azure Marketplace Template - Implementation Plan

**Status:** Approved by Neo4j Infrastructure Team
**Date:** January 29, 2026
**Template Location:** `/Users/ryanknight/projects/neo4j-partners/azure-resource-manager-neo4j`

---

## Outstanding Questions

The following questions need to be confirmed before release:

1. **Testing Environment**: Is there a staging/preview environment for testing marketplace submissions before going live? *(Azure Partner Center has preview/staging capabilities - confirm workflow)*

2. **Rollback Capability**: Can marketplace image versions be rolled back instantly, or is there a review/approval delay?

---

## Current Template State - Key Findings

### Region Handling
- **No region restrictions** in createUiDefinition.json or main.bicep
- Template accepts any Azure region via `location()` function
- **Risk:** Deployment will fail in regions without Premium SSD v2 or required VM sizes

### Zone Configuration Issues
| Resource | Current State | Issue |
|----------|---------------|-------|
| VMSS | No zones (regional) | Cannot use Premium SSD v2 |
| Load Balancer Public IP | Hardcoded `['1','2','3']` | Fails in regions with <3 zones |

### Storage Configuration
- Current: `Premium_LRS` (Premium SSD)
- Current: `caching: 'None'` ✓ (already correct for Premium SSD v2)
- No `diskControllerType` specified (allows Azure to auto-select)

### VM Size Restrictions
- Current: `excludedSizes` with only `Standard_B1s`, `Standard_B1ls` (insufficient)
- **Plan:** Switch to `allowedSizes` with ~50 curated VMs (E, D, L, FX series)

### Cloud-Init NVMe Compatibility
- **Current disk path:** `/dev/disk/azure/scsi1/lun0` (SCSI only)
- **NVMe path would be:** `/dev/disk/azure/nvme/by-lun/0`
- **Solution:** Use `/dev/disk/azure/data/by-lun/0` which works for both SCSI and NVMe

---

## Overview

This document outlines the implementation plan for upgrading the Neo4j Azure Marketplace template. Changes are organized into phases with testing checkpoints to ensure each change works before moving to the next.

### Key Changes

1. **NVMe Support:** Enable support for NVMe disk controllers, unlocking FX-series and v6-series VMs
2. **Zonal Deployment:** Convert VMSS from regional to zonal deployment (required for Premium SSD v2)
3. **Premium SSD v2:** Upgrade from Premium SSD to Premium SSD v2 for better price-performance
4. **Universal Disk Path:** Update cloud-init to use `/dev/disk/azure/data/by-lun/0` (works for both SCSI and NVMe)
5. **VM Allowlist:** Switch to `allowedSizes` with ~50 curated, tested VM sizes (E, D, L, FX series)
6. **Reliability:** Add retry logic, memory validation, and improved error handling

### Architecture Impact

| Aspect | Current | After Implementation |
|--------|---------|---------------------|
| VMSS Type | Regional (no zones) | Zonal (with zones parameter) |
| Storage | Premium_LRS (Premium SSD) | PremiumV2_LRS (Premium SSD v2) |
| Disk Path | `/dev/disk/azure/scsi1/lun0` | `/dev/disk/azure/data/by-lun/0` |
| Disk Controller | SCSI only (implicit) | Auto-select (SCSI or NVMe) |
| VM Selection | `excludedSizes` (2 VMs blocked) | `allowedSizes` (~50 curated VMs) |
| LB Public IP Zones | Hardcoded `['1','2','3']` | Parameterized |

---

## Phase 1: Enable NVMe Support, Zonal Deployment, and Upgrade Storage

This is the most critical phase. These changes unlock newer VM families and improve storage performance.

**⚠️ IMPORTANT:** Premium SSD v2 requires zonal VMSS deployment. This is a significant architecture change from the current regional deployment model.

### 1.1 Update the Marketplace Image Definition for NVMe Support

**What to change:**
- Update the Azure Marketplace image definition to include NVMe support
- Add the DiskControllerTypes feature flag to advertise both SCSI and NVMe support
- The flag should be set to "SCSI,NVMe" to support both controller types

**Files affected:**
- Azure Marketplace image definition (managed through Azure Partner Center)

**Owner:** Ryan Knight

**Why this matters:**
- Unlocks v6-series and FX-series VMs for customers
- Aligns with Neo4j's official recommendation for NVMe storage
- Future-proofs the template as Azure moves toward NVMe as default

---

### 1.2 Convert VMSS from Regional to Zonal Deployment

**What to change:**
- Add `zones` property to VMSS resource (required for Premium SSD v2)
- Add `platformFaultDomainCount: 1` (required for zonal VMSS)
- Update load balancer public IP to use dynamic zone configuration instead of hardcoded `['1','2','3']`
- Consider zone-balancing strategy for multi-node clusters

**Current state:**
```bicep
// vmss.bicep - NO zones (regional deployment)
resource vmScaleSets 'Microsoft.Compute/virtualMachineScaleSets@2025-04-01' = {
  name: vmScaleSetsName
  location: location
  // zones: NOT SPECIFIED - regional deployment
```

```bicep
// loadbalancer.bicep - HARDCODED zones
zones: [
  '2'
  '3'
  '1'
]
```

**Target state:**
```bicep
// vmss.bicep - zonal deployment
resource vmScaleSets 'Microsoft.Compute/virtualMachineScaleSets@2025-04-01' = {
  name: vmScaleSetsName
  location: location
  zones: zones  // Pass as parameter, e.g., ['1', '2', '3'] or ['1'] for single-zone
  properties: {
    platformFaultDomainCount: 1  // Required for zonal VMSS
    // ...
  }
}
```

**Files affected:**
- marketplace/neo4j-enterprise/modules/vmss.bicep
- marketplace/neo4j-enterprise/modules/loadbalancer.bicep
- marketplace/neo4j-enterprise/main.bicep (add zones parameter)

**Why this matters:**
- **REQUIRED** for Premium SSD v2 - cannot use PremiumV2_LRS with regional VMSS
- Improves availability by distributing VMs across zones
- Fixes current bug where hardcoded zones fail in regions with <3 AZs

**Zone handling options:**
1. **Simple:** Default to zone `['1']` (single zone, works everywhere with AZs)
2. **Balanced:** Use `['1', '2', '3']` where available, fall back to fewer
3. **Configurable:** Add UI parameter for zone selection

---

### 1.3 Update Cloud-Init for Universal Disk Path (SCSI + NVMe)

**What to change:**
- Change disk path from SCSI-specific to universal path that works with both controllers
- Update all three cloud-init YAML files

**Current state (SCSI-only):**
```yaml
disk_setup:
  /dev/disk/azure/scsi1/lun0:
    table_type: gpt
    layout: true
    overwrite: false

fs_setup:
  - device: /dev/disk/azure/scsi1/lun0
    partition: 1
    filesystem: xfs

mounts:
  - ["/dev/disk/azure/scsi1/lun0-part1", "/var/lib/neo4j", "xfs", "defaults", "0", "0"]
```

**Target state (universal path):**
```yaml
disk_setup:
  /dev/disk/azure/data/by-lun/0:
    table_type: gpt
    layout: true
    overwrite: false

fs_setup:
  - device: /dev/disk/azure/data/by-lun/0
    partition: 1
    filesystem: xfs

mounts:
  - ["/dev/disk/azure/data/by-lun/0-part1", "/var/lib/neo4j", "xfs", "defaults", "0", "0"]
```

**Files affected:**
- scripts/neo4j-enterprise/cloud-init/standalone.yaml
- scripts/neo4j-enterprise/cloud-init/cluster.yaml
- scripts/neo4j-enterprise/cloud-init/read-replica.yaml

**Why this matters:**
- `/dev/disk/azure/data/by-lun/0` works for **both SCSI and NVMe** controllers
- Without this change, NVMe VMs will fail to mount the data disk
- Azure creates this symlink automatically regardless of controller type

---

### 1.4 Update VMSS Storage Profile for Dual Controller Support

**What to change:**
- Do NOT specify `diskControllerType` - let Azure auto-select based on VM family
- This allows the same template to work with both SCSI (older VMs) and NVMe (newer VMs)

**Current state:**
```bicep
storageProfile: {
  // diskControllerType: NOT SPECIFIED (good - allows auto-selection)
  osDisk: { ... }
  dataDisks: [{ ... }]
}
```

**Recommendation:** Keep current behavior (no explicit diskControllerType). Azure will:
- Use SCSI for E-series v5, D-series v5, and older families
- Use NVMe for v6-series, FX-series, and newer families

**Files affected:**
- marketplace/neo4j-enterprise/modules/vmss.bicep (verify no hardcoded controller type)

---

### 1.5 Upgrade Storage from Premium SSD to Premium SSD v2

**What to change:**
- Change `storageAccountType` from `Premium_LRS` to `PremiumV2_LRS`
- Ensure `caching: 'None'` is set (already correct in current template)
- Optionally add IOPS and throughput parameters for advanced users

**Current state:**
```bicep
dataDisks: [
  {
    lun: 0
    createOption: 'Empty'
    managedDisk: {
      storageAccountType: 'Premium_LRS'  // Change this
    }
    caching: 'None'  // Already correct ✓
    diskSizeGB: diskSize
  }
]
```

**Target state:**
```bicep
dataDisks: [
  {
    lun: 0
    createOption: 'Empty'
    managedDisk: {
      storageAccountType: 'PremiumV2_LRS'
      // Optional: diskIOPSReadWrite and diskMBpsReadWrite for custom performance
    }
    caching: 'None'
    diskSizeGB: diskSize
  }
]
```

**Files affected:**
- marketplace/neo4j-enterprise/modules/vmss.bicep
- marketplace/neo4j-enterprise/main.bicep (optional: add IOPS/throughput parameters)

**Why this matters:**
- Better price-performance than Premium SSD
- Allows customers to adjust IOPS and throughput without recreating disks
- Baseline 3,000 IOPS / 125 MB/s included free

**Optional enhancement - configurable performance:**
```bicep
// main.bicep
@minValue(3000)
@maxValue(80000)
param diskIOPS int = 3000

@minValue(125)
@maxValue(1200)
param diskThroughputMBps int = 125
```

---

### Testing Checkpoint 1: Zonal, NVMe, and Storage Validation

**Prerequisites:**
- Marketplace image updated with NVMe support (1.1 complete)
- All template changes deployed to test environment

**Test the following before proceeding to Phase 2:**

1. **Test zonal deployment in multi-AZ region (East US 2)**
   - Deploy standalone Neo4j with zones: ['1', '2', '3']
   - Verify VMSS instances distribute across zones
   - Verify load balancer public IP is zone-redundant

2. **Test single-zone deployment**
   - Deploy standalone Neo4j with zones: ['1']
   - Verify deployment succeeds

3. **Deploy with E-series v5 VM (SCSI-capable)**
   - Verify the VM deploys successfully
   - Verify Neo4j starts and is accessible
   - Verify data disk is attached and mounted at /var/lib/neo4j
   - Verify Premium SSD v2 is being used: `az disk show --ids <disk-id> --query sku.name`
   - Verify disk appears via universal path: `ls -la /dev/disk/azure/data/by-lun/`

4. **Deploy with v6-series VM (NVMe-only)**
   - Verify the VM deploys successfully with NVMe disk controller
   - Verify Neo4j starts and is accessible
   - Verify data disk is attached and mounted correctly
   - Verify disk appears via universal path (same as SCSI)

5. **Deploy with FX-series VM**
   - Same verification steps as above
   - Confirm this VM family that previously failed now works

6. **Run basic Neo4j operations on each deployment**
   - Create nodes and relationships
   - Run a simple Cypher query
   - Verify data persists after Neo4j restart

7. **Test region with limited AZs (if available)**
   - Deploy to a region with only 1-2 availability zones
   - Verify deployment handles zone configuration gracefully

**Pass criteria:** All VM types deploy successfully with zonal configuration, Premium SSD v2, and Neo4j operates normally.

---

## Phase 2: Update VM Size Restrictions

With NVMe support enabled, we can now support newer VM families. Using `allowedSizes` (whitelist) instead of `excludedSizes` (blocklist) for better maintainability.

### 2.1 Switch to Allowlist Approach

**Why `allowedSizes` is better than `excludedSizes`:**

| Aspect | `excludedSizes` (current) | `allowedSizes` (new) |
|--------|---------------------------|----------------------|
| List size | ~100+ VMs to block | ~40 curated VMs |
| Maintenance | Must block new ARM64/small VMs | Add new VMs when validated |
| New Azure VMs | Auto-appear (risky) | Don't appear until added |
| User experience | See everything except blocked | See only supported VMs |

**What to change:**
- Replace `excludedSizes` with `allowedSizes`
- Curate a list of tested, supported VM sizes
- Organize by use case (memory-optimized, general purpose, storage-optimized, compute-optimized)

**Current state:**
```json
"constraints": {
  "excludedSizes": [
    "Standard_B1s",
    "Standard_B1ls"
  ]
}
```

**Target state:**
```json
"constraints": {
  "allowedSizes": [
    "Standard_E4s_v5",
    "Standard_E8s_v5",
    "Standard_E16s_v5",
    "Standard_E20s_v5",
    "Standard_E32s_v5",
    "Standard_E48s_v5",
    "Standard_E64s_v5",
    "Standard_E96s_v5",
    "Standard_E4ds_v5",
    "Standard_E8ds_v5",
    "Standard_E16ds_v5",
    "Standard_E20ds_v5",
    "Standard_E32ds_v5",
    "Standard_E48ds_v5",
    "Standard_E64ds_v5",
    "Standard_E96ds_v5",
    "Standard_E4s_v6",
    "Standard_E8s_v6",
    "Standard_E16s_v6",
    "Standard_E32s_v6",
    "Standard_E48s_v6",
    "Standard_E64s_v6",
    "Standard_E96s_v6",
    "Standard_D4s_v5",
    "Standard_D8s_v5",
    "Standard_D16s_v5",
    "Standard_D32s_v5",
    "Standard_D48s_v5",
    "Standard_D64s_v5",
    "Standard_D4ds_v5",
    "Standard_D8ds_v5",
    "Standard_D16ds_v5",
    "Standard_D32ds_v5",
    "Standard_D48ds_v5",
    "Standard_D64ds_v5",
    "Standard_D4s_v6",
    "Standard_D8s_v6",
    "Standard_D16s_v6",
    "Standard_D32s_v6",
    "Standard_D48s_v6",
    "Standard_D64s_v6",
    "Standard_L8s_v3",
    "Standard_L16s_v3",
    "Standard_L32s_v3",
    "Standard_L48s_v3",
    "Standard_L64s_v3",
    "Standard_L80s_v3",
    "Standard_FX4mds",
    "Standard_FX12mds",
    "Standard_FX24mds",
    "Standard_FX36mds",
    "Standard_FX48mds"
  ]
}
```

**Files affected:**
- marketplace/neo4j-enterprise/createUiDefinition.json

**VM families included:**

| Family | Use Case | Why Include |
|--------|----------|-------------|
| E-series v5/v6 | Memory-optimized | Best for Neo4j - high memory-to-CPU ratio |
| D-series v5/v6 | General purpose | Good alternative, common quota availability |
| L-series v3 | Storage-optimized | Large local NVMe, good for big graphs |
| FX-series | Compute-optimized | High CPU frequency for complex queries |

**VM families NOT included (and why):**

| Family | Reason Excluded |
|--------|-----------------|
| A-series | No Premium Storage support |
| B-series | Burstable, insufficient consistent performance |
| ARM64 (*p* VMs) | Image is x64 only |
| F-series (non-FX) | Low memory-to-CPU ratio |
| H-series | HPC-focused, overkill for Neo4j |
| M-series | Extremely large, specialized |
| N-series | GPU-focused, unnecessary cost |

---

### 2.2 Update Recommended VM Sizes

**What to change:**
- Update `recommendedSizes` to highlight best options
- First size becomes the default if available in region

**Target state:**
```json
"recommendedSizes": [
  "Standard_E4s_v5",
  "Standard_E8s_v5",
  "Standard_E16s_v5",
  "Standard_E32s_v5",
  "Standard_D4s_v5",
  "Standard_D8s_v5",
  "Standard_E4s_v6",
  "Standard_E8s_v6"
]
```

**Files affected:**
- marketplace/neo4j-enterprise/createUiDefinition.json

---

### 2.3 Memory Enforcement

**What to change:**
- No additional UI changes needed - `allowedSizes` naturally excludes small VMs
- All VMs in the allowlist have ≥16 GB memory (smallest is E4s_v5 with 32 GB)
- Cloud-init memory check (Phase 3.3) provides defense in depth

---

### Testing Checkpoint 2: VM Size Restrictions

**Test the following before proceeding to Phase 3:**

1. **Verify only allowed VMs are selectable**
   - Open the Azure Marketplace deployment UI
   - Confirm only E-series, D-series, L-series, and FX-series VMs appear
   - Confirm ARM64 VMs (e.g., Standard_D4ps_v5) do NOT appear
   - Confirm A-series, B-series VMs do NOT appear

2. **Verify NVMe VMs work**
   - Deploy using Standard_FX4mds - should succeed
   - Deploy using Standard_E4s_v6 - should succeed
   - Deploy using Standard_D4s_v6 - should succeed

3. **Verify recommended VMs work correctly**
   - Deploy using Standard_E4s_v5 (first recommended) - should succeed
   - Deploy using Standard_D4s_v5 - should succeed

4. **Verify L-series works (if testing storage-optimized)**
   - Deploy using Standard_L8s_v3 - should succeed

**Pass criteria:** Only curated VMs are selectable, all allowed VM types deploy successfully.

---

## Phase 3: High Priority Fixes

These fixes address reliability issues observed in production deployments.

**Note:** Cloud-init scripts already exist at `scripts/neo4j-enterprise/cloud-init/*.yaml` and are in use via the `cloudInitBase64` parameter in vmss.bicep.

### 3.1 Add Password Length Validation at Template Level

**What to change:**
- Add `@minLength(8)` and `@maxLength(72)` decorators to the adminPassword parameter
- This ensures validation occurs even for direct ARM API deployments that bypass the UI

**Current state:**
```bicep
@secure()
param adminPassword string
```

**Target state:**
```bicep
@secure()
@minLength(8)
@maxLength(72)
@description('Admin password for Neo4j and SSH access. Must be 8-72 characters.')
param adminPassword string
```

**Files affected:**
- marketplace/neo4j-enterprise/main.bicep

**Why this matters:**
- UI already validates 12-72 chars with complexity (exceeds Neo4j requirements)
- But ARM API deployments can bypass UI validation
- Neo4j minimum is 8 characters; Azure maximum is 72

---

### 3.2 Add Retry Logic for Package Repository Operations

**What to change:**
- Add retry wrapper function for package operations
- Wait for any existing package manager locks before proceeding
- Retry RPM key import and DNF install operations (5 attempts, 10-second delays)

**Add to runcmd section:**
```yaml
runcmd:
  # Wait for any existing package manager locks
  - |
    wait_for_lock() {
      local max_attempts=30
      local attempt=1
      while fuser /var/lib/rpm/.rpm.lock >/dev/null 2>&1 || \
            fuser /var/lib/dnf/lock/download_lock.pid >/dev/null 2>&1; do
        if [ $attempt -ge $max_attempts ]; then
          echo "ERROR: Package manager lock not released after $max_attempts attempts"
          exit 1
        fi
        echo "Waiting for package manager lock (attempt $attempt/$max_attempts)..."
        sleep 10
        attempt=$((attempt + 1))
      done
    }
    wait_for_lock

  # Import Neo4j GPG key with retry
  - |
    for i in {1..5}; do
      rpm --import https://debian.neo4j.com/neotechnology.gpg.key && break
      echo "RPM key import failed (attempt $i/5), retrying in 10s..."
      sleep 10
    done

  # Install Neo4j with retry
  - |
    for i in {1..5}; do
      dnf install -y neo4j-enterprise && break
      echo "DNF install failed (attempt $i/5), retrying in 10s..."
      sleep 10
    done
```

**Files affected:**
- scripts/neo4j-enterprise/cloud-init/standalone.yaml
- scripts/neo4j-enterprise/cloud-init/cluster.yaml
- scripts/neo4j-enterprise/cloud-init/read-replica.yaml

---

### 3.3 Add Memory Validation Before Installation

**What to change:**
- Add memory check at the start of runcmd
- Fail with clear error if below 3500 MB (allows headroom on 4GB VMs)

**Add to beginning of runcmd section:**
```yaml
runcmd:
  # Validate system has sufficient memory for Neo4j
  - |
    TOTAL_MEM_MB=$(free -m | awk '/^Mem:/{print $2}')
    MIN_MEM_MB=3500
    if [ "$TOTAL_MEM_MB" -lt "$MIN_MEM_MB" ]; then
      echo "ERROR: Insufficient memory for Neo4j installation"
      echo "Required: ${MIN_MEM_MB}MB, Available: ${TOTAL_MEM_MB}MB"
      echo "Please use a VM with at least 4GB of RAM"
      exit 1
    fi
    echo "Memory check passed: ${TOTAL_MEM_MB}MB available"
```

**Files affected:**
- scripts/neo4j-enterprise/cloud-init/standalone.yaml
- scripts/neo4j-enterprise/cloud-init/cluster.yaml
- scripts/neo4j-enterprise/cloud-init/read-replica.yaml

---

### 3.4 Add Password Length Validation in Cloud-Init

**What to change:**
- Add password length check after base64 decoding
- Fail with clear error if password is too short

**Add to password configuration section:**
```yaml
  - |
    # Decode base64-encoded password
    PASSWORD_BASE64='${admin_password}'
    ADMIN_PASSWORD=$(echo "$PASSWORD_BASE64" | base64 -d)

    # Validate password length (defense in depth)
    if [ ${#ADMIN_PASSWORD} -lt 8 ]; then
      echo "ERROR: Password must be at least 8 characters"
      echo "Received password of length: ${#ADMIN_PASSWORD}"
      exit 1
    fi
    echo "Password validation passed"
```

**Files affected:**
- scripts/neo4j-enterprise/cloud-init/standalone.yaml
- scripts/neo4j-enterprise/cloud-init/cluster.yaml
- scripts/neo4j-enterprise/cloud-init/read-replica.yaml

---

### Testing Checkpoint 3: High Priority Fixes

**Test the following before proceeding to Phase 4:**

1. **Password validation - Template level**
   - Attempt deployment with a 7-character password via ARM CLI:
     ```bash
     az deployment group create ... --parameters adminPassword="short12"
     ```
   - Verify deployment is rejected with validation error

2. **Password validation - Cloud-init level**
   - Check cloud-init logs: `sudo cat /var/log/cloud-init-output.log`
   - Verify password validation message appears

3. **Package manager retry logic**
   - Deploy normally and verify successful installation
   - Check cloud-init logs for retry logic messages
   - Verify no failures due to package lock contention

4. **Memory validation**
   - Deploy on a VM with 4 GB RAM (e.g., Standard_B2ms)
   - Verify deployment succeeds
   - Check logs: `grep "Memory check" /var/log/cloud-init-output.log`

**Pass criteria:** Password validation rejects short passwords at template level, package installation is resilient, memory check passes on 4GB+ VMs.

---

## Phase 4: Remaining Fixes

These are defensive measures and user experience improvements.

### 4.1 Add Deployment Timeout Handling and Logging

**What to change:**
- Add explicit timeout values for long-running operations in cloud-init scripts
- Add health check commands that verify each installation step completed
- Log completion timestamps for major installation phases

**Add timestamp logging:**
```yaml
runcmd:
  - echo "=== Neo4j Installation Started: $(date -Iseconds) ==="

  # ... existing steps ...

  - echo "=== Package Installation Complete: $(date -Iseconds) ==="

  # ... Neo4j configuration ...

  - echo "=== Neo4j Configuration Complete: $(date -Iseconds) ==="

  # ... service start ...

  - echo "=== Neo4j Service Started: $(date -Iseconds) ==="
```

**Add timeout to Neo4j readiness check:**
```yaml
  # Wait for Neo4j to be ready (with timeout)
  - |
    TIMEOUT=300
    ELAPSED=0
    until curl -s -o /dev/null -w '%{http_code}' http://localhost:7474 | grep -q "200"; do
      if [ $ELAPSED -ge $TIMEOUT ]; then
        echo "ERROR: Neo4j failed to start within ${TIMEOUT} seconds"
        exit 1
      fi
      echo "Waiting for Neo4j to be ready... (${ELAPSED}s elapsed)"
      sleep 5
      ELAPSED=$((ELAPSED + 5))
    done
    echo "=== Neo4j Ready: $(date -Iseconds) ==="
```

**Files affected:**
- scripts/neo4j-enterprise/cloud-init/standalone.yaml
- scripts/neo4j-enterprise/cloud-init/cluster.yaml
- scripts/neo4j-enterprise/cloud-init/read-replica.yaml

---

### 4.2 Document Concurrent Deployment Limitations

**What to change:**
- Add documentation noting that customers should not run multiple Neo4j deployments simultaneously to the same resource group
- Current resource naming uses `uniqueString(resourceGroup().id)` which would conflict

**Files affected:**
- Documentation/README files
- Consider adding info text in createUiDefinition.json

**Note:** The template already uses `uniqueString(resourceGroup().id)` for resource naming, which prevents conflicts within the same resource group over time, but concurrent deployments to the same RG would still conflict.

---

### 4.3 Maintain Robust Password Handling

**What to change:**
- Add comments in cloud-init scripts explaining why base64 encoding is used
- Document that passwords should never be passed as command-line arguments

**Add documentation comment:**
```yaml
  # SECURITY NOTE: Password is passed via base64 encoding to avoid:
  # 1. Shell interpretation of special characters ($, !, ", ', etc.)
  # 2. Exposure in process listings (ps aux)
  # 3. Logging of sensitive data in command history
  # DO NOT revert to passing passwords as command-line arguments.
  - |
    PASSWORD_BASE64='${admin_password}'
    ADMIN_PASSWORD=$(echo "$PASSWORD_BASE64" | base64 -d)
```

**Files affected:**
- scripts/neo4j-enterprise/cloud-init/standalone.yaml
- scripts/neo4j-enterprise/cloud-init/cluster.yaml
- scripts/neo4j-enterprise/cloud-init/read-replica.yaml

---

### ~~4.4 Optimize Installation Order~~ (REMOVED)

**Reason for removal:** Azure CLI is NOT currently installed in the cloud-init scripts. The standalone.yaml only installs Neo4j and its dependencies. No reordering is needed.

---

### Testing Checkpoint 4: Final Validation

**Complete end-to-end testing:**

1. **Standalone deployment - E-series v5 VM (SCSI)**
   - Full deployment from marketplace UI
   - Verify Neo4j is accessible and operational
   - Test with special characters in password: `Test@Pass!2024$`
   - Verify timestamps appear in cloud-init logs

2. **Standalone deployment - D-series v5 VM**
   - Full deployment using new recommended D-series
   - Verify all functionality

3. **Standalone deployment - E-series v6 VM (NVMe)**
   - Full deployment using newly enabled NVMe VM
   - Verify disk mounted via universal path
   - Verify all functionality

4. **Cluster deployment (3 nodes)**
   - Deploy a 3-node cluster
   - Verify cluster formation: `SHOW SERVERS`
   - Verify all nodes are operational
   - Verify data replicates across nodes

5. **Cluster deployment (5 nodes, multi-zone)**
   - Deploy a 5-node cluster across 3 zones
   - Verify zone distribution
   - Verify cluster remains operational if one zone fails

6. **Edge cases**
   - Password with special characters: `Test'Pass"With!$pecial`
   - Maximum password length (72 characters)
   - Deployment in different regions (East US, West Europe, Southeast Asia)

**Pass criteria:** All deployment types succeed, Neo4j is fully operational, timestamps logged correctly, no regressions from previous template version.

---

## Phase 5: Release

### 5.1 Update Version Numbers

**What to change:**
- Increment template version number
- Update changelog with summary of changes

**Files affected:**
- Version files in the template
- CHANGELOG.md or release notes

---

### 5.2 Submit to Azure Marketplace

**What to change:**
- Submit updated template to Azure Marketplace for review
- Update marketplace listing description if needed to reflect new capabilities

---

### 5.3 Monitor Initial Deployments

**Post-release monitoring:**
- Monitor QoS data for the first week after release
- Watch for any new failure patterns
- Be prepared to rollback if critical issues emerge

---

## Summary: Files to Modify

| File | Phase | Changes |
|------|-------|---------|
| **Azure Marketplace image definition** | 1.1 | Enable NVMe support (`DiskControllerTypes=SCSI,NVMe`) |
| **vmss.bicep** | 1.2, 1.4, 1.5 | Add zones parameter, platformFaultDomainCount, PremiumV2_LRS storage |
| **loadbalancer.bicep** | 1.2 | Replace hardcoded zones with parameter, zone-aware configuration |
| **main.bicep** | 1.2, 1.5, 3.1 | Add zones parameter, optional IOPS/throughput params, password validation decorators |
| **createUiDefinition.json** | 2.1, 2.2 | Switch to `allowedSizes` whitelist (~50 curated VMs), updated recommended sizes |
| **standalone.yaml** | 1.3, 3.2-3.4, 4.1, 4.3 | Universal disk path, retry logic, memory check, password validation, timeout handling, logging |
| **cluster.yaml** | 1.3, 3.2-3.4, 4.1, 4.3 | Same as standalone.yaml |
| **read-replica.yaml** | 1.3, 3.2-3.4, 4.1, 4.3 | Same as standalone.yaml |
| **Documentation** | 4.2 | Concurrent deployment warnings |

### Change Summary by File

**vmss.bicep changes:**
```bicep
// Add
param zones array = ['1']

resource vmScaleSets ... = {
  zones: zones
  properties: {
    platformFaultDomainCount: 1
    virtualMachineProfile: {
      storageProfile: {
        dataDisks: [{
          managedDisk: {
            storageAccountType: 'PremiumV2_LRS'  // Changed from Premium_LRS
          }
        }]
      }
    }
  }
}
```

**Cloud-init changes (all 3 files):**
```yaml
# Disk path change
disk_setup:
  /dev/disk/azure/data/by-lun/0:  # Changed from /dev/disk/azure/scsi1/lun0

# New: Memory validation, package retry logic, password validation, timeout handling
```

**createUiDefinition.json changes:**
- Replace `excludedSizes` with `allowedSizes` (whitelist approach)
- Curated list of ~50 supported VMs (E-series, D-series, L-series, FX-series)
- Update `recommendedSizes` to include D-series v5 and E-series v6

---

## Rollback Plan

If critical issues are discovered after release:

1. Revert the marketplace image to the previous version without NVMe support
2. Revert the template files to the previous version
3. Document the issue and root cause
4. Plan fixes for the next release cycle

---

## Timeline Estimate

- Phase 1 (NVMe + Storage): Implement and test
- Phase 2 (VM Restrictions): Implement and test
- Phase 3 (High Priority Fixes): Implement and test
- Phase 4 (Remaining Fixes): Implement and test
- Phase 5 (Release): Submit and monitor

Each phase should be completed and tested before moving to the next.
