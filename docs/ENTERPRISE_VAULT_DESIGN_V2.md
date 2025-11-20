# Azure Key Vault Integration for Neo4j Enterprise Deployment (VAULT_V2)

**Date:** 2025-11-18
**Status:** Combined Proposal

---

## Executive Summary

This document combines and updates the proposals for integrating Azure Key Vault into the Neo4j Enterprise Azure deployment. The goal is to provide secure, centralized, and auditable secret management, supporting both Azure Marketplace and direct deployment scenarios, while maintaining backward compatibility.

---

## 1. Current State Analysis

- Secrets (e.g., adminPassword, license keys) are passed as `@secure()` parameters in Bicep templates and handled by deployment scripts.
- Passwords may be exposed in deployment metadata, local files, or logs, despite `@secure()` marking.
- Partial Key Vault support exists in deployment tooling, but not end-to-end in the Bicep/VM lifecycle.

---

## 2. Proposed Architecture

### 2.1 Design Principles
- **Security First:** Secrets never written to disk or logs; only resolved at runtime.
- **Backward Compatibility:** Existing deployments continue to work; migration path provided.
- **Marketplace Compatibility:** Supports both new and existing Key Vaults; can auto-create vaults for Marketplace users.
- **Operational Simplicity:** Minimal workflow changes; clear documentation.
- **Enterprise Ready:** Centralized management, RBAC, audit, and policy support.

### 2.2 Key Vault Integration Patterns
- **User-Managed Key Vault:** User creates and manages vault, provides reference to deployment.
- **Template-Managed Key Vault:** Bicep template creates vault and manages secrets for Marketplace simplicity.
- **Hybrid Approach:** Template supports all modes via a `keyVaultMode` parameter.

### 2.3 Password Retrieval by VMs
- **Cloud-Init Approach (Recommended):**
  - VM boots with Managed Identity.
  - Cloud-init retrieves password from Key Vault using Azure REST API and access token.
  - Password used in memory only, never written to disk.

---

## 3. Implementation Phases

### Phase 1: Foundation
- Add optional Key Vault parameters to Bicep.
- Update deployment scripts to support vault creation and secret storage.
- Maintain backward compatibility with direct password parameter.

### Phase 2: Cloud-Init Vault Retrieval
- VMs retrieve passwords from Key Vault at runtime using Managed Identity.
- Remove password from deployment metadata.

### Phase 3: Marketplace Integration
- Update `createUiDefinition.json` to support vault options (auto-create, existing, or direct input).
- Bicep template can create vault and generate/store password if needed.

---

## 4. Bicep Template Changes

- Remove direct secret parameters:
  ```bicep
  // REMOVE
  @secure()
  param adminPassword string
  param graphDataScienceLicenseKey string = 'None'
  param bloomLicenseKey string
  ```
- Add Key Vault reference parameters:
  ```bicep
  // ADD
  @description('Name of the Azure Key Vault containing the deployment secrets.')
  param keyVaultName string
  @description('The name of the secret in the Key Vault that holds the admin password for the Neo4j VMs.')
  param adminPasswordSecretName string = 'neo4j-admin-password'
  @description('The name of the secret for the Graph Data Science license key.')
  param graphDataScienceLicenseKeySecretName string = 'neo4j-gds-license'
  @description('The name of the secret for the Bloom license key.')
  param bloomLicenseKeySecretName string = 'neo4j-bloom-license'
  ```
- Fetch secrets from Key Vault in Bicep:
  ```bicep
  resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
    name: keyVaultName
  }
  var adminPassword = keyVault.getSecret(adminPasswordSecretName)
  var graphDataScienceLicenseKey = keyVault.getSecret(graphDataScienceLicenseKeySecretName)
  var bloomLicenseKey = keyVault.getSecret(bloomLicenseKeySecretName)
  ```
- Pass secrets to modules as needed.

---

## 5. Marketplace UI Changes

- Update `createUiDefinition.json` to allow users to:
  - Select password management mode (auto-create vault, use existing, or direct input).
  - Provide vault name or select existing vault.
  - Input secret names if needed.
  - Warn if direct password input is selected.

---

## 6. Security Considerations

- The deploying identity must have `get` permission for Key Vault secrets.
- Managed Identity for VMs must be granted "Key Vault Secrets User" role.
- Enable soft delete and purge protection on vaults.
- No secret values are output or stored in deployment metadata.

---

## 7. Password Generation Best Practices - Implementation Todos

This section provides an actionable todo list for implementing secure password generation and storage using shell scripts and Key Vault. The intent is to minimize exposure, simplify operations, and support both local and Marketplace scenarios without embedding passwords in infrastructure definitions.

### 7.1 Overall Strategy

**Two Deployment Paths:**

1. **Local/Enterprise Deployments** (Automated)
   - `deployments/` scripts call `generate-password.sh` to create password
   - Script stores password in Key Vault using Azure CLI
   - Bicep deployment uses vault name + secret name (no password parameter)
   - Cloud-init retrieves password from vault at runtime using managed identity
   - ✅ Fully automated, zero password exposure

2. **Azure Marketplace Deployments** (User-Provided Vault)
   - User creates Key Vault BEFORE marketplace deployment
   - User generates and stores password in vault (we provide documentation/commands)
   - User selects "Use Key Vault" option in marketplace UI
   - User provides vault name + secret name
   - Bicep deployment retrieves password from vault
   - Cloud-init uses same vault retrieval mechanism
   - ✅ No password in marketplace UI, secure but requires pre-deployment steps

**Why This Approach:**
- Marketplace doesn't execute shell scripts (`deploy.sh` is local testing only)
- Can't generate passwords securely in ARM/Bicep templates
- User-provided vault is most secure option for marketplace
- Automation possible for local/enterprise deployments

### 7.2 Goals
- Eliminate plain password parameters from deployment metadata
- Centralize generation and storage in Key Vault
- Ensure repeatable local testing and validation
- Provide a gradual path from manual input to fully automated vault usage
- Keep tooling simple: shell script for password generation (minimal dependencies)

### 7.3 Implementation Todos

#### Phase 1: Create Local Password Generation Script ✓ COMPLETED
- [x] Create `scripts/generate-password.sh` shell script with the following features:
  - [x] Generate strong password (32+ characters, mixed case, numbers, special chars)
  - [x] Accept optional length parameter (default: 32)
  - [x] Output password to stdout for use in deployment scripts
  - [x] Return exit code 0 on success, non-zero on failure
  - [x] Add usage documentation in script header
- [x] Test script locally
- [x] Verify password strength meets requirements (openssl)
- [x] Verify script is simple, portable, and has minimal dependencies

**Implementation Notes:**
- Script location: `scripts/generate-password.sh` (< 50 lines)
- Uses OpenSSL for cryptographically strong password generation
- Default password length: 32 characters with guaranteed character diversity
- Simple design: just generates and outputs password (no Key Vault logic)
- Usage: `PASSWORD=$(./scripts/generate-password.sh)`
- Test results: Password contains uppercase, lowercase, digits, and special characters
- Key Vault integration will happen in deployment scripts (Phase 3)

#### Phase 2: Local Testing and Validation ✓ COMPLETED
- [x] ~~Create or reuse test Key Vault for validation~~ (Not needed - script just generates passwords)
- [x] Document test procedure in README
- [x] Run generation script and verify password output
- [x] ~~Test retrieval from Key Vault~~ (Deferred to Phase 3 - deployment integration)
- [x] ~~Confirm access control and audit logging~~ (Deferred to Phase 3)
- [x] Record test results (password length, complexity validation)
- [x] ~~Clean up test resources~~ (Not needed - no infrastructure created)

**Implementation Notes:**
- Validated password generation works correctly
- Password complexity verified: uppercase, lowercase, digits, special chars
- Multiple runs produce unique passwords
- Script is clean, simple, portable (47 lines total)
- Minimal dependencies: bash, openssl (both standard on Azure CLI environments)
- Key Vault integration will be added in Phase 3 deployment scripts

#### Phase 3: Local/Enterprise Deployment Integration ✓ COMPLETED
**Goal:** Automate password generation and Key Vault storage for local deployments using `deployments/` scripts

- [x] Update `deployments/src/password.py` PasswordManager class:
  - [x] Added `generate_and_store_in_keyvault()` method
  - [x] Calls `scripts/generate-password.sh` to generate password
  - [x] Stores password in Key Vault using `az keyvault secret set`
  - [x] Returns vault parameters for Bicep deployment
  - [x] Enhanced `_get_from_keyvault()` to auto-generate if secret doesn't exist
- [x] Updated `deployments/src/deployment.py`:
  - [x] Modified `_inject_dynamic_values()` to use vault parameters when available
  - [x] Passes `keyVaultName` and `adminPasswordSecretName` to Bicep instead of password
  - [x] Updated `_validate_parameters()` to allow empty adminPassword when using Key Vault
  - [x] Maintains backward compatibility with direct password mode

**Implementation Notes:**
- PasswordManager now supports AZURE_KEYVAULT strategy with auto-generation
- When strategy is AZURE_KEYVAULT, password is generated using `generate-password.sh` and stored in vault
- Deployment scripts retrieve password from vault and pass it as @secure parameter to Bicep (for VM OS profile)
- Vault parameters are also passed to cloud-init for Neo4j password retrieval at runtime
- Password Manager caches vault name for parameter generation
- **Important Architecture Note**: Azure requires a valid password for VM's osProfile.adminPassword. When using Key Vault mode:
  - Password is retrieved from vault and passed as @secure parameter (Azure encrypts it in deployment metadata)
  - Same password is used for VM OS admin account
  - Cloud-init retrieves the same password from vault for Neo4j (using managed identity, more secure than embedding in template)

**Auto-Create Vault Feature:** ✅ ADDED
- Added `PasswordManager.create_keyvault()` static method
- Integrated with setup wizard (`deployments/src/setup.py`)
- During setup, user can choose to:
  - Create new Key Vault (auto-created with access policies)
  - Use existing Key Vault
- Vault is created in separate resource group (`{prefix}-keyvault`)
- Persists across deployments (not deleted with test resources)
- Automatic access policy grant for current user
- Files modified: `deployments/src/password.py`, `deployments/src/setup.py`, `deployments/src/deployment.py`

#### Phase 4: Bicep Template Updates (Support Both Modes) ✓ COMPLETED
**Goal:** Update Bicep to support optional Key Vault while maintaining backward compatibility

- [x] Add optional Key Vault parameters to `main.bicep`:
  - [x] `param keyVaultName string = ''` (empty = use direct password)
  - [x] `param adminPasswordSecretName string = 'neo4j-admin-password'`
  - [x] Modified `@secure() param adminPassword string = ''` to have default empty value
- [x] Added conditional logic in Bicep:
  - [x] Variable `useKeyVault` determines mode based on `keyVaultName` parameter
  - [x] Variable `passwordPlaceholder` set to 'RETRIEVE_FROM_KEYVAULT' when using vault
  - [x] Variables `vaultNameForCloudInit` and `secretNameForCloudInit` passed to cloud-init
- [x] Updated cloud-init template replacements:
  - [x] Added `${key_vault_name}` and `${admin_password_secret_name}` placeholders
  - [x] Applied to both standalone/cluster and read-replica templates
  - [x] Maintains backward compatibility with direct password mode

**Implementation Notes:**
- Bicep template now accepts three parameters: `adminPassword`, `keyVaultName`, `adminPasswordSecretName`
- If `keyVaultName` is provided, password is set to 'RETRIEVE_FROM_KEYVAULT' placeholder
- Cloud-init receives vault parameters and decides at runtime which mode to use
- Fully backward compatible: existing deployments with direct password still work
- Files modified: `marketplace/neo4j-enterprise/main.bicep`

#### Phase 4.5: Cloud-Init Vault Retrieval and Managed Identity Access ✓ COMPLETED
**Goal:** Update cloud-init scripts to retrieve passwords from Key Vault at runtime

- [x] Updated `scripts/neo4j-enterprise/cloud-init/standalone.yaml`:
  - [x] Added Key Vault retrieval logic using Azure IMDS (Instance Metadata Service)
  - [x] Retrieves access token using managed identity
  - [x] Fetches secret from vault using REST API
  - [x] Falls back to direct password if vault not configured
  - [x] Sets Neo4j initial password using retrieved or direct value
- [x] Updated `scripts/neo4j-enterprise/cloud-init/cluster.yaml`:
  - [x] Same vault retrieval logic as standalone
  - [x] Works for all cluster nodes
- [x] Updated `scripts/neo4j-enterprise/cloud-init/read-replica.yaml`:
  - [x] Same vault retrieval logic for read replicas
  - [x] Supports Neo4j 4.4 read replicas

**Implementation Notes:**
- Cloud-init checks if `${key_vault_name}` is provided and password is 'RETRIEVE_FROM_KEYVAULT'
- If yes, uses IMDS to get OAuth token for https://vault.azure.net resource
- Retrieves secret using Key Vault REST API (no Azure CLI needed on VM)
- Password never written to disk, only used in memory
- Requires managed identity with "Key Vault Secrets User" role on the vault
- Files modified: `standalone.yaml`, `cluster.yaml`, `read-replica.yaml`

**Managed Identity Access (Automated):** ✅ ADDED
- [x] Created `marketplace/neo4j-enterprise/modules/keyvault-access.bicep`:
  - [x] New module for granting Key Vault access to managed identity
  - [x] Supports cross-resource-group deployment (vault in different RG than deployment)
  - [x] Grants `get` and `list` permissions on secrets
- [x] Updated `marketplace/neo4j-enterprise/main.bicep`:
  - [x] Added `keyVaultResourceGroup` parameter for cross-resource-group vault access
  - [x] Added module invocation for Key Vault access policy (scoped to vault's resource group)
  - [x] Only activates when `keyVaultName` parameter is provided
- [x] Updated `marketplace/neo4j-enterprise/modules/identity.bicep`:
  - [x] Added `identityPrincipalId` output for access policy assignment
- [x] Updated `deployments/src/password.py`:
  - [x] Caches vault resource group name (follows naming convention: `{prefix}-keyvault`)
  - [x] Passes resource group to Bicep deployment
  - [x] Fixed password storage to use subprocess (avoids shell quoting issues with special characters)
- [x] Updated `deployments/src/deployment.py`:
  - [x] Passes `keyVaultResourceGroup` parameter to Bicep

**Implementation Notes:**
- Managed identity is automatically granted access to Key Vault during deployment
- No manual access policy setup required
- Vault can be in different resource group than deployment (supports setup wizard pattern)
- Password stored in vault without quotes (fixed shell escaping issue)

#### Phase 5: Standardized Naming and Team Adoption
- [ ] Document naming convention for vaults and secrets
  - [ ] Example: `kv-${environment}-neo4j`, secret: `neo4j-admin-password`
- [ ] Create deployment checklist:
  - [ ] Vault exists in correct subscription/region
  - [ ] Secret created using generation script
  - [ ] Access validated
  - [ ] Rotation date recorded (if applicable)
- [ ] Enforce script usage (no manual password entry)
- [ ] Add team documentation and training materials

#### Phase 6: Password Rotation Support
- [ ] Add rotation mode to `generate-password.sh`:
  - [ ] Accept `--rotate` flag to update existing secret
  - [ ] Generate new password and create new secret version
  - [ ] Log rotation event (timestamp, initiator)
- [ ] Document rotation procedure:
  - [ ] Run rotation script
  - [ ] Plan maintenance window for Neo4j restart
  - [ ] Update Neo4j configuration with new password
  - [ ] Verify cluster health after rotation
- [ ] Add retention policy for old secret versions

#### Phase 7: Marketplace Integration (User-Provided Vault)
**Goal:** Allow marketplace users to provide existing Key Vault instead of entering password directly

**Approach:** User creates vault and password BEFORE marketplace deployment

- [ ] Update `createUiDefinition.json` to support Key Vault mode:
  - [ ] Add password mode selector: "Use existing Key Vault" or "Enter password directly"
  - [ ] If vault mode: show Key Vault resource selector
  - [ ] If vault mode: add secret name input (default: `neo4j-admin-password`)
  - [ ] If direct mode: show existing password box (current behavior)
  - [ ] Add info box explaining vault benefits
- [ ] Create marketplace pre-deployment documentation:
  - [ ] Guide: "Using Key Vault with Neo4j Marketplace Deployment"
  - [ ] Step 1: Create Key Vault in Azure Portal
  - [ ] Step 2: Generate password (provide Azure CLI command or use Cloud Shell)
  - [ ] Step 3: Store secret in vault
  - [ ] Step 4: Deploy from marketplace selecting vault mode
  - [ ] Include example Azure CLI commands
- [ ] Test Marketplace deployment flow:
  - [ ] Test with existing vault (vault mode)
  - [ ] Test with direct password (backward compatibility)
- [ ] Update marketplace listing description to mention Key Vault support

**Important:** Marketplace users must pre-create vault and password. The `generate-password.sh` script is for local/enterprise deployments only.

#### Phase 8: Optional Auto-Create Vault (Future)
- [ ] Add Bicep module to optionally create Key Vault
- [ ] Accept parameter: `createKeyVault` (true/false)
- [ ] If true, create vault and generate password via deployment script
- [ ] Still avoid embedding password generation in Bicep itself
- [ ] Document this option for first-time users

### 7.3 Validation Checklist (Per Deployment)
Before each deployment confirm:
- [ ] Vault exists in correct subscription and region
- [ ] Secret name matches documented convention
- [ ] Generation script completed without warnings
- [ ] Retrieval test succeeds: `az keyvault secret show`
- [ ] No password value in logs, terminal history, or parameter files
- [ ] Audit entry recorded in Key Vault logs

### 7.4 Success Indicators
- Zero password exposure incidents post-adoption
- Consistent secret naming across all environments
- Reduced manual intervention during deployments
- Clear audit trails for all password operations
- Faster, safer password rotations

### 7.5 Technical Notes
- **Why shell script over Python?** For Bicep deployments, Azure CLI is already required. A shell script has zero additional dependencies and is simpler to audit and maintain for this single-purpose task.
- **Deferment:** Native Bicep-based password generation is intentionally deferred to avoid accidental exposure and keep logic centralized in one audited script.

---

## 8. Action Plan

1. Update deployment scripts to manage Key Vault and secrets lifecycle.
2. Modify Bicep templates to remove direct secret parameters and add Key Vault references.
3. Update cloud-init to retrieve secrets from Key Vault at runtime.
4. Update Marketplace UI and documentation.
5. Test all scenarios and document migration steps.

---

## 9. References
- MODERN.md (Recommendation 3)
- Azure Key Vault documentation
- Azure Marketplace certification requirements

---

*This document supersedes previous proposals in KEY_VAULT_PROPOSAL.md and VAULT.md.*
