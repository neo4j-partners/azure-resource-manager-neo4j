# Localtests Bicep Migration Updates

**Date:** 2025-11-17
**Status:** Complete

---

## Summary

Updated the localtests framework to work with the migrated Bicep templates for Neo4j Enterprise standalone deployments.

---

## Changes Made

### 1. Deployment Engine (`src/deployment.py`)

**Auto-detect Bicep vs JSON templates:**
- Now checks for `mainTemplate.bicep` first
- Falls back to `mainTemplate.json` if Bicep not found
- Sets `self.is_bicep` flag for conditional logic

```python
# Before: Only looked for mainTemplate.json
self.template_file = base_template_dir / "mainTemplate.json"

# After: Prefers Bicep, falls back to JSON
if self.template_file_bicep.exists():
    self.template_file = self.template_file_bicep
    self.is_bicep = True
elif self.template_file_json.exists():
    self.template_file = self.template_file_json
    self.is_bicep = False
```

**Skip _artifactsLocation for standalone Bicep:**
- Standalone deployments (nodeCount=1) with Bicep use embedded cloud-init
- No external scripts needed, so `_artifactsLocation` parameter is skipped
- Cluster deployments (nodeCount>1) still use external scripts temporarily

```python
# Only inject _artifactsLocation for JSON templates or cluster deployments
node_count = p.get("nodeCount", {}).get("value", 1)
if not self.is_bicep or node_count > 1:
    set_param("_artifactsLocation", artifacts_location)
else:
    # Standalone Bicep uses cloud-init - no external scripts
    pass
```

### 2. Scenario Definitions (`.arm-testing/config/scenarios.yaml`)

**Updated to match Bicep parameters:**

```yaml
# Before (old container-based parameters):
scenarios:
  - name: standalone-v5
    container_cpu: '2.0'
    container_memory: '4'
    storage_quota_gb: 100

# After (VM-based Bicep parameters):
scenarios:
  - name: standalone-v5
    vm_size: 'Standard_E4s_v5'
    disk_size: 32
    install_graph_data_science: false
    graph_data_science_license_key: 'None'
    install_bloom: false
    bloom_license_key: 'None'
    read_replica_count: 0
```

### 3. Default Scenarios (`src/setup.py`)

**Already correct!** The `_create_default_scenarios()` method was already using proper Bicep parameters:
- `vm_size` instead of `container_cpu`
- `disk_size` instead of `storage_quota_gb`
- All plugin and read replica parameters included

### 4. Data Models (`src/models.py`)

**Already correct!** The `TestScenario` model already had all the right fields matching Bicep:
- `vm_size: str`
- `disk_size: int`
- `read_replica_count: int`
- `install_graph_data_science: bool`
- `graph_data_science_license_key: str`
- `install_bloom: bool`
- `bloom_license_key: str`

---

## How It Works Now

### Standalone Deployments (nodeCount=1)

1. **Template Detection:** Finds `mainTemplate.bicep`
2. **Parameter Generation:** Creates parameters matching Bicep schema
3. **No External Scripts:** Skips `_artifactsLocation` parameter
4. **Cloud-Init:** Uses embedded cloud-init YAML (no downloads)
5. **Deployment:** Azure CLI compiles Bicep automatically

### Cluster Deployments (nodeCount≥3)

1. **Template Detection:** Finds `mainTemplate.bicep`
2. **Parameter Generation:** Includes `_artifactsLocation` parameter
3. **External Scripts:** Still uses bash scripts from GitHub (temporary)
4. **Deployment:** Azure CLI compiles Bicep automatically

---

## Usage

The framework works exactly as before:

```bash
# Run setup (creates correct scenarios automatically)
uv run test-arm.py setup

# Validate Bicep templates
uv run test-arm.py validate

# Deploy standalone with cloud-init
uv run test-arm.py deploy --scenario standalone-v5

# Deploy cluster (still uses bash scripts)
uv run test-arm.py deploy --scenario cluster-3node-v5

# Check status
uv run test-arm.py status

# Clean up
uv run test-arm.py cleanup --all
```

---

## What's Different

| Aspect | Before | After |
|--------|--------|-------|
| **Template Type** | ARM JSON only | Bicep (preferred) or JSON |
| **Standalone Scripts** | Downloaded from GitHub | Embedded cloud-init YAML |
| **Cluster Scripts** | Downloaded from GitHub | Still downloaded (temporary) |
| **_artifactsLocation** | Always required | Only for clusters |
| **Parameters** | Container-based | VM-based (Azure VMs) |
| **Compilation** | N/A | Azure CLI compiles Bicep |

---

## Future Work

When cluster deployments are migrated to cloud-init:

1. Update `_inject_dynamic_values()` to never inject `_artifactsLocation`
2. Remove `_artifactsLocation` from base `parameters.json`
3. Update scenarios for cluster-specific cloud-init parameters (if any)

---

## Testing

To verify the updates work:

```bash
# Test standalone deployment with Bicep + cloud-init
cd localtests
uv run test-arm.py setup  # If not already done
uv run test-arm.py deploy --scenario standalone-v5 --wait

# Verify it uses cloud-init (no external scripts)
# Check deployment output for: "Standalone Bicep deployment - using embedded cloud-init"
```

---

**Last Updated:** 2025-11-17
