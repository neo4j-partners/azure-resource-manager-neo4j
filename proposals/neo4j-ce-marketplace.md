# Proposal: Neo4j Community Edition Azure Marketplace Template

## Problem Statement

The Azure Marketplace currently only offers Neo4j Enterprise Edition through our ARM templates. Users who want to run Neo4j Community Edition on Azure have no one-click deployment option from the marketplace. This forces CE users to manually provision VMs, install Neo4j, configure networking, and manage disk setup themselves. The result is a poor onboarding experience for developers, hobbyists, and small teams who want to evaluate or run Neo4j without an Enterprise license.

The existing Enterprise template also installs Enterprise-only plugins (GDS, Bloom), uses an Enterprise marketplace VM image (neo4j-ee-vm with BYOL plan), accepts an Enterprise license agreement, and supports multi-node clustering. None of these features apply to Community Edition. We cannot simply reuse the Enterprise template with a different parameter; the template needs to be purpose-built for CE constraints.

## Proposed Solution

Create a new, standalone marketplace offering at `marketplace/neo4j-ce/` that deploys a single Neo4j Community Edition node on an Azure VM Scale Set (capacity 1). This template will share the same modular Bicep pattern as the Enterprise template (network, identity, vmss modules) but will be stripped of all Enterprise-only features.

The CE template will:

- Deploy exactly one VM (no clustering, no load balancer)
- Install the `neo4j` package instead of `neo4j-enterprise`
- Skip GDS, Bloom, and other Enterprise plugin configuration
- Use an approved Azure Marketplace base Linux image (RHEL 9) with Neo4j installed entirely via cloud-init at first boot
- Remove the license type parameter entirely (CE has no license agreement prompt)
- Remove the node count parameter (always 1)
- Include APOC as the only plugin, since it ships with CE
- Retain the same network security, disk setup, and memory tuning as Enterprise standalone

The end result is a simpler, lighter template that gives CE users the same deployment convenience Enterprise users already have.

## Requirements

1. The CE template must deploy a single Neo4j Community Edition node that is reachable over Bolt (port 7687) and HTTP (port 7474) from the public internet.

2. The CE template must not reference or install any Enterprise-only features: no clustering, no GDS, no Bloom, no license agreement environment variable, no BYOL plan, no custom Neo4j VM image.

3. The CE template must use the same modular Bicep structure as Enterprise (network, identity, vmss modules) so the two offerings stay consistent and maintainable.

4. The CE template must have its own cloud-init script under `scripts/neo4j-ce/cloud-init/standalone.yaml` that installs the `neo4j` package (not `neo4j-enterprise`).

5. The CE template must have its own `createUiDefinition.json` for the marketplace portal, with only the parameters that apply to CE (admin username, password, VM size, disk size, database version).

6. The deployment testing framework must support CE scenarios alongside Enterprise scenarios without breaking existing functionality.

7. The CE template must pass Bicep linting with the existing `bicepconfig.json` rules (no hardcoded secrets, secure parameters, etc.).

8. The CE offering must be packageable via a `makeArchive.sh` script for upload to the Azure Partner Portal.

---

## Implementation Plan

### Step 1: Create the CE directory structure

Create the following directory layout, mirroring the Enterprise offering:

```
marketplace/neo4j-ce/
  main.bicep
  parameters.json
  createUiDefinition.json
  deploy.sh
  makeArchive.sh
  modules/
    network.bicep
    identity.bicep
    vmss.bicep
```

No `loadbalancer.bicep` module is needed since CE is always a single node.

### Step 2: Create the CE cloud-init script

Create `scripts/neo4j-ce/cloud-init/standalone.yaml` based on the Enterprise standalone cloud-init, with the following changes:

- Replace `dnf install -y neo4j-enterprise` with `dnf install -y neo4j`
- Remove the `NEO4J_ACCEPT_LICENSE_AGREEMENT` environment variable and the systemd license override file (CE does not require license acceptance)
- Remove all GDS and Bloom plugin configuration lines
- Remove the `dbms.security.procedures.unrestricted=gds.*` setting
- Remove the `bloom.*` entries from the procedure allowlist and HTTP auth allowlist
- Remove the unmanaged extension class configuration for Bloom
- Keep APOC installation (move from labs to plugins), memory tuning, SSRF protection, routing configuration, disk setup, and password handling exactly as they are

No cluster cloud-init is needed for CE.

### Step 3: Build the CE Bicep modules

**network.bicep** - Copy directly from Enterprise. The NSG rules are identical (SSH, HTTP, HTTPS, Bolt). Remove the cluster communication rules (port 6000 and port 7000) since CE does not support clustering.

**identity.bicep** - Copy directly from Enterprise with no changes.

**vmss.bicep** - Copy from Enterprise with the following changes:

- Remove the `plan` block entirely (CE uses an approved base image, not the Enterprise BYOL marketplace image)
- Change the `imageReference` to use a standard RHEL 9 base image from the Azure Marketplace (publisher: RedHat, offer: RHEL, sku: 9-lvm-gen2). RHEL 9 is chosen because the Enterprise cloud-init scripts already use `dnf` and `rpm` commands, so the CE scripts stay consistent. The RHEL 9 base image has cloud-init pre-installed and is an Azure-approved base, which simplifies marketplace certification.
- Remove the `licenseType` tag; replace with `Neo4jEdition: 'Community'` as a fixed tag
- Remove the `loadBalancerBackendAddressPools` parameter and the conditional load balancer attachment
- Hard-code the SKU capacity to 1

### Step 4: Build the CE main.bicep

Create `marketplace/neo4j-ce/main.bicep` with these differences from Enterprise:

- Remove the `licenseType` parameter
- Remove the `nodeCount` parameter (hard-code to 1)
- Remove the load balancer module reference entirely
- Remove the cluster cloud-init path and the standalone/cluster conditional
- Remove the `licenseAgreement` variable and the cloud-init replacement step for `${license_agreement}`
- Remove the `nodeCount` cloud-init replacement step
- Keep the cloud-init replacements for `${unique_string}`, `${location}`, and `${admin_password}`
- Reference `scripts/neo4j-ce/cloud-init/standalone.yaml` instead of the Enterprise path
- Simplify outputs: only the single-node browser URL, username, and resource IDs (no cluster browser URL, no load balancer outputs)

### Step 5: Create the CE createUiDefinition.json

Create a marketplace UI definition with only these fields:

- Admin username (text box, same validation as Enterprise)
- Admin password (password box, same validation as Enterprise)
- VM size (size selector, same recommended sizes)
- Disk size (dropdown, same options)
- Graph database version (dropdown, currently just "5")

Remove: node count dropdown, license type dropdown.

### Step 6: Create the CE parameters.json

Create a default parameters file for local testing with sensible defaults:

- vmSize: Standard_E4s_v5
- diskSize: 32
- graphDatabaseVersion: "5"
- adminPassword: (empty, must be provided at deploy time)

### Step 7: Create deploy.sh and makeArchive.sh

**deploy.sh** - Copy from Enterprise and modify to reference `main.bicep` in the CE directory. Remove any cluster-related parameter handling. The script should compile `main.bicep` to `mainTemplate-generated.json`, deploy it, and clean up.

**makeArchive.sh** - Copy from Enterprise and modify to package the CE template files into `archive.zip` for marketplace upload. The archive must include `mainTemplate.json` and `createUiDefinition.json`.

### Step 8: VM image strategy — Approved Base + cloud-init

The CE template will use a standard RHEL 9 base image from the Azure Marketplace (an Azure-approved base) and install Neo4j Community Edition entirely through cloud-init at first boot. No custom or pre-baked Neo4j VM image is needed.

This approach was chosen because:

- It eliminates the need to build and maintain a custom image pipeline (Packer, Azure Image Builder, Azure Compute Gallery, Partner Center RBAC)
- It matches the pattern the Enterprise template already uses (cloud-init does the heavy lifting)
- OS patches and security updates come from RedHat automatically, with no image rebuild required on our side
- Neo4j version updates require only a change to the yum repo URL in the cloud-init script, not a full image rebuild and publish cycle
- Azure-approved base images have billing metadata and OS layout pre-configured, simplifying marketplace certification
- The trade-off is slightly longer first-boot provisioning (~3-5 minutes extra for package download and install), which is acceptable for a single-node CE deployment that users provision once and run long-term

The `vmss.bicep` module will have no `plan` block and will reference the standard RHEL 9 image (publisher: RedHat, offer: RHEL, sku: 9-lvm-gen2, version: latest). The cloud-init YAML will add the Neo4j yum repository, import the GPG key, and install the `neo4j` package on first boot.

---

## Testing Plan

### Update the Pydantic models in `deployments/src/models.py`

**TestScenario model:**

- Add `"Community"` as an allowed value for the `license_type` field. The current allowed values are `"Enterprise"` and `"Evaluation"`. Change the `Literal` to `Literal["Enterprise", "Evaluation", "Community"]`.
- Add a validator that enforces `node_count == 1` when `license_type` is `"Community"`.
- Add a validator that enforces `install_graph_data_science` is `False` and `install_bloom` is `False` when `license_type` is `"Community"`.

**DeploymentType enum:**

- No changes needed. CE still uses VM deployment (DeploymentType.VM).

### Update the deployment engine in `deployments/src/deployment.py`

The deployment engine currently loads Bicep templates from `marketplace/neo4j-enterprise/`. It needs to select the template directory based on the scenario's license type:

- If `license_type` is `"Community"`, load templates from `marketplace/neo4j-ce/`
- Otherwise, load from `marketplace/neo4j-enterprise/`

The parameter file generation must also change for CE scenarios: do not include `licenseType` or `nodeCount` parameters since those do not exist in the CE template.

### Update the orchestrator in `deployments/src/orchestrator.py`

The orchestrator submits deployments and extracts outputs. For CE scenarios:

- The deployment submission logic should work without changes (it just points to a different template file)
- Output extraction needs to handle the simplified CE outputs (no cluster browser URL, no load balancer address)
- Connection info parsing should set `license_type` to `"Community"` and `node_count` to `1`

### Update the validator in `deployments/src/validate_deploy.py`

The Neo4j validator connects to the deployed instance and runs checks. For CE scenarios:

- Skip any license type validation that checks for Enterprise features
- The Movies dataset test (create and verify nodes) should work identically on CE since it uses standard Cypher
- Add a CE-specific check that confirms the instance is running Community Edition (query `dbms.components()` and verify the edition field says "community")
- Skip any GDS or Bloom connectivity checks

### Add CE test scenarios to `scenarios.yaml`

Add at minimum these two scenarios:

1. **standalone-ce-v5** - Single node, Community Edition, Neo4j 5, Standard_E4s_v5, 32GB disk. This is the basic smoke test.

2. **standalone-ce-v5-large** - Single node, Community Edition, Neo4j 5, Standard_E8s_v5, 128GB disk. This tests a larger VM and disk size to validate resource scaling.

### Add a GitHub Actions workflow

Create `.github/workflows/community.yml` that mirrors the Enterprise workflow structure:

- Trigger on pull requests that modify files under `marketplace/neo4j-ce/` or `scripts/neo4j-ce/`
- Compile Bicep to ARM JSON
- Deploy the standalone-ce-v5 scenario to a temporary resource group
- Run `uv run validate_deploy standalone-ce-v5` to verify the deployment
- Clean up the resource group

### Manual testing checklist

Before merging, manually verify:

- The CE template compiles without Bicep linting errors
- A standalone CE deployment completes successfully in Azure
- Neo4j is reachable on port 7474 (HTTP) and 7687 (Bolt) from the public internet
- The admin password set during deployment works for authentication
- APOC procedures are available (run `CALL apoc.help("apoc")` and verify results)
- GDS and Bloom are not installed (calling `gds.version()` should fail)
- The instance reports Community Edition when querying `CALL dbms.components()`
- The `makeArchive.sh` script produces a valid `archive.zip`
- The `deploy.sh` script works end-to-end from a clean state

---

## Summary

This proposal adds a Community Edition marketplace offering that mirrors the existing Enterprise structure but is stripped down to match CE capabilities: single node, no clustering, no Enterprise plugins, no license agreement. The CE template uses a standard RHEL 9 approved base image from the Azure Marketplace with Neo4j installed entirely via cloud-init at first boot, avoiding the need for a custom image build pipeline. The testing framework gets updated to handle CE as a first-class scenario type with its own template path, simplified parameters, and edition-specific validation checks. The implementation is a clean, separate directory under `marketplace/neo4j-ce/` with its own cloud-init scripts, avoiding any compatibility layers or conditional Enterprise/CE logic in the existing Enterprise template.
