# CE VM Image Build & Deployment Tracking

Status tracking for the Neo4j Community Edition marketplace VM image (`neo4j-ce-vm`).

## Gallery Image Details

| Property | Value |
|----------|-------|
| Resource Group | `neo4j-ce-image-rg` |
| Gallery | `neo4jmarketplace` |
| Image Definition | `neo4j-ce-vm` |
| Image Version | `1.1.0` |
| Source VM Size | `Standard_D2ds_v6` (NVMe-capable) |
| Source Image | `RedHat:RHEL:9-lvm-gen2:latest` |
| Disk Controller | NVMe |
| Security Type | TrustedLaunch |
| Replication Regions | eastus2, northcentralus |

### Image Definition Features (Immutable)

```
SecurityType=TrustedLaunch
DiskControllerTypes=SCSI,NVMe
IsAcceleratedNetworkSupported=True
```

## Issues Found & Fixed

### Issue 1: Gallery Image Not Replicated to Deployment Region

**Error:** `InvalidParameter` — gallery image not found in westus2

**Root Cause:** Image v1.1.0 was only replicated to eastus2. Deployments targeting other regions (e.g. westus2) couldn't find the image.

**Fix:**
- Redesigned test scenarios with per-scenario `region` fields to target only replicated regions
- Added `--target-regions "${REGION}" "northcentralus"` to `makeVm.sh` so replication happens at capture time
- Added `region` field to `TestScenario` model in `deployments/src/models.py`

**Files Changed:**
- `marketplace/neo4j-ce/makeVm.sh` — added `--target-regions`
- `deployments/src/models.py` — added `region` field to `TestScenario`
- `deployments/src/deployment.py` — use `scenario.region` override
- `deployments/src/setup.py` — 3 new CE test scenarios with explicit regions

---

### Issue 2: NVMe Disk Controller Incompatibility

**Error:** `InvalidParameter` — The VM size 'Standard_E4ds_v6' cannot boot with OS image or disk. Please check that disk controller types supported by the OS image or disk is one of the supported disk controller types for the VM size.

**Root Cause:** The gallery image v1.1.0 was captured from a source VM running `Standard_D2s_v5` — a SCSI-only v5 VM. Azure validates the **actual captured disk metadata**, not just the image definition features. Even though the definition declared `DiskControllerTypes=SCSI,NVMe`, the VHD itself was SCSI-only.

**Key Insight (from Microsoft docs):** The image version must be created from an NVMe-supported VHD. NVMe support begins with Ebsv5 and v6+ VM sizes. The Dsv5 family does not support NVMe.

**Fix:**
- Changed `VM_SIZE` from `Standard_D2s_v5` to `Standard_D2ds_v6` in `makeVm.sh`
- Added explicit `--disk-controller-type NVMe` to `az vm create`
- Rebuilt image v1.1.0 from the NVMe source VM

**Verification:**
```bash
# Confirmed source VM disk controller type
az vm show --resource-group neo4j-ce-image-rg --name neo4j-ce-image-vm \
  --query "storageProfile.diskControllerType" -o tsv
# Result: NVMe  ✓
```

**Files Changed:**
- `marketplace/neo4j-ce/makeVm.sh` — `VM_SIZE=Standard_D2ds_v6`, `--disk-controller-type NVMe`

**Microsoft Docs References:**
- [NVMe FAQ: How to create image definition supporting NVMe](https://learn.microsoft.com/azure/virtual-machines/enable-nvme-remote-faqs#how-do-i-create-an-image-definition-that-supports-nvme-for-remote-disks)
- [NVMe Overview: Supported VM families](https://learn.microsoft.com/azure/virtual-machines/nvme-overview)

---

### Issue 3: Trusted Launch Security Profile Required

**Error:** `BadRequest` — The provided gallery image only supports creation of VMs and VM Scale Sets with 'TrustedLaunch' security type.

**Root Cause:** The image definition was created with `SecurityType=TrustedLaunch` feature. VMs deployed from this image must explicitly set `securityType: 'TrustedLaunch'` in their `securityProfile`. The Bicep VM template did not include this.

**Fix:** Added `securityProfile` block to `marketplace/neo4j-ce/modules/vm.bicep`:

```bicep
securityProfile: {
  securityType: 'TrustedLaunch'
  uefiSettings: {
    secureBootEnabled: true
    vTpmEnabled: true
  }
}
```

**Files Changed:**
- `marketplace/neo4j-ce/modules/vm.bicep` — added `securityProfile`

---

### Issue 4: Missing `galleryImageId` in Settings

**Error:** Deployment used marketplace image reference instead of gallery image, causing `InvalidParameter` (marketplace offer not yet published).

**Root Cause:** `ce_gallery_image_id` was defined in the `Settings` model but was never written to `settings.yaml`. The deployment code checked `self.settings.ce_gallery_image_id` which was `None`, so it fell through to the marketplace image reference.

**Fix:** Added `ce_gallery_image_id` to `deployments/.arm-testing/config/settings.yaml`:

```yaml
ce_gallery_image_id: /subscriptions/47fd4ce5-a912-480e-bb81-95fbd59bb6c5/resourceGroups/neo4j-ce-image-rg/providers/Microsoft.Compute/galleries/neo4jmarketplace/images/neo4j-ce-vm/versions/1.1.0
```

**Files Changed:**
- `deployments/.arm-testing/config/settings.yaml`

---

## Test Matrix

Three CE test scenarios covering all deployment paths:

| Scenario | VM Size | Region | Zone | Disk Controller | Disk SKU | Status |
|----------|---------|--------|------|-----------------|----------|--------|
| ce-zonal-nvme | Standard_E4ds_v6 | eastus2 | Yes (zone 1) | NVMe | PremiumV2_LRS | **Deployed + Validated** |
| ce-zonal-scsi | Standard_E4s_v5 | eastus2 | Yes (zone 1) | SCSI | PremiumV2_LRS | **Deployed + Validated** |
| ce-nonzonal | Standard_E4s_v5 | northcentralus | No | SCSI | Premium_LRS | **Deployed + Validated** |

### Previous Test Results (Before NVMe/TrustedLaunch Fixes)

| Scenario | Result | Error |
|----------|--------|-------|
| ce-zonal-nvme | **Failed** | NVMe disk controller incompatibility (Issue 2) |
| ce-zonal-scsi | Succeeded | — |
| ce-nonzonal | Succeeded | — |

### Issue 5: Accelerated Networking Not Enabled on NIC

**Error:** No deployment error — but the NIC was deployed without `enableAcceleratedNetworking: true`, despite the image definition declaring `IsAcceleratedNetworkSupported=True`.

**Root Cause:** The NIC resource in `vm.bicep` didn't set the `enableAcceleratedNetworking` property. Azure doesn't auto-enable it; it must be explicitly set.

**Impact:** Without accelerated networking, the VM uses software-based networking instead of SR-IOV hardware offload. This reduces network throughput and increases latency. All allowed VM sizes (4+ vCPUs for v5, all v6) support it.

**Fix:** Added `enableAcceleratedNetworking: true` to the NIC resource properties in `vm.bicep`.

**Files Changed:**
- `marketplace/neo4j-ce/modules/vm.bicep` — added `enableAcceleratedNetworking: true`

---

## Publishing Readiness Review

### What's Correct

| Component | Status | Details |
|-----------|--------|---------|
| Image definition features | Correct | `SecurityType=TrustedLaunch`, `DiskControllerTypes=SCSI,NVMe`, `IsAcceleratedNetworkSupported=True` |
| Gen2 image | Correct | `--hyper-v-generation V2` + `RHEL:9-lvm-gen2:latest` base |
| Trusted Launch in Bicep | Correct | `securityProfile` with `secureBootEnabled` + `vTpmEnabled` |
| NVMe source VM | Correct | `Standard_D2ds_v6` with `--disk-controller-type NVMe` |
| Accelerated networking | Correct | `enableAcceleratedNetworking: true` on NIC |
| PremiumV2_LRS data disk | Correct | Zonal regions only, `caching: 'None'` (required) |
| Premium_LRS fallback | Correct | Non-zonal regions get Premium_LRS without zone |
| Cloud-init NVMe handling | Correct | Uses `/dev/disk/azure/data/by-lun/` symlinks (works with both SCSI and NVMe) |
| Marketplace plan block | Correct | Skipped for gallery/test images, present for marketplace |
| Recommended VM sizes | Correct | v6 NVMe sizes first, v5 SCSI sizes also allowed |
| OS disk type | Correct | `Premium_LRS` (PremiumV2_LRS cannot be used for OS disks) |

### Partner Center Checklist

When publishing v1.1.0 in Partner Center Technical Configuration:

- [ ] Image type: **x64 Gen 2**
- [ ] Security type: **Trusted Launch**
- [ ] Check: **Supports NVMe**
- [ ] Check: **Supports accelerated networking**
- [ ] Gallery: `neo4jmarketplace`, Image: `neo4j-ce-vm`, Version: `1.1.0`
- [ ] Recommended VM sizes: `Standard_E4ds_v6`, `Standard_E2ds_v6`, `Standard_E8ds_v6`

### Known Limitations

1. **PremiumV2_LRS regional availability** — If a region has availability zones but doesn't support PremiumV2_LRS, the disk creation fails. Mitigated by the allowed VM sizes list covering widely-available regions.
2. **SecurityType=TrustedLaunch** (not TrustedLaunchSupported) — VMs from this image can ONLY be Trusted Launch. `TrustedLaunchSupported` would allow both Gen2 and Trusted Launch. This is acceptable since the Bicep template always sets Trusted Launch.
3. **Trusted Launch + NVMe constraint** — VMs deployed with Trusted Launch SCSI cannot convert to NVMe afterward. New VMs must be created with the desired disk controller from the start.

## Files Modified (All Changes)

| File | Changes |
|------|---------|
| `marketplace/neo4j-ce/makeVm.sh` | VM_SIZE → D2ds_v6, `--disk-controller-type NVMe`, `--target-regions` |
| `marketplace/neo4j-ce/modules/vm.bicep` | `securityProfile` (Trusted Launch), `enableAcceleratedNetworking: true` |
| `marketplace/neo4j-ce/main.bicep` | Added `galleryImageId` parameter, 3-way image selection |
| `deployments/src/models.py` | Added `region` to TestScenario, `ce_gallery_image_id` to Settings |
| `deployments/src/deployment.py` | Use `scenario.region` override, pass `galleryImageId` param |
| `deployments/src/setup.py` | 3 CE test scenarios (zonal-nvme, zonal-scsi, nonzonal), region display |
| `deployments/src/commands/deploy.py` | Fixed region display bug (2 locations) |

## Validation Results

All 3 scenarios: ARM deployment succeeded, Neo4j Community Edition verified, Movies CRUD dataset created + verified (11 nodes).

| Scenario | Bolt Endpoint | Edition | CRUD |
|----------|--------------|---------|------|
| ce-zonal-nvme | `neo4j-p3dreto7d35fc.eastus2.cloudapp.azure.com:7687` | community | Pass |
| ce-zonal-scsi | `neo4j-y7qsune4ctsg2.eastus2.cloudapp.azure.com:7687` | community | Pass |
| ce-nonzonal | `neo4j-6uf2kf2x4conu.northcentralus.cloudapp.azure.com:7687` | community | Pass |

## Next Steps

1. ~~Validate all 3 CE deployments succeed~~ — **Done**
2. ~~Run Neo4j connectivity tests~~ — **Done**
3. **Clean up test deployments** — `cd deployments && uv run neo4j-deploy cleanup --all --force`
4. **Publish in Partner Center** — Upload v1.1.0, check "Supports NVMe" and "Supports accelerated networking"
5. **Compile main.json** — Final ARM JSON for marketplace submission
6. **Clean up gallery resources** — Delete `neo4j-ce-image-rg` after marketplace publishing
