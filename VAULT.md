# Azure Key Vault Integration for Neo4j Enterprise Deployment

**Date:** 2025-11-18
**Status:** Proposal
**Related:** MODERN.md (Recommendation 3: Secure Secret Management via Azure Key Vault)

## Executive Summary

This document proposes a phased implementation of Azure Key Vault integration for secure password management in the Neo4j Enterprise Azure deployment. The solution addresses current security limitations while maintaining backward compatibility and supporting both Azure Marketplace and direct deployment scenarios.

## 1. Current State Analysis

### 1.1 Current Password Handling Architecture

**Bicep Template Level (mainTemplate.bicep)**:
- Password accepted as secure parameter marked with `@secure()` decorator (line 1-2)
- Password embedded into cloud-init YAML via string replacement (line 76)
- Base64-encoded cloud-init data passed to VM as customData (line 82)

**Cloud-Init Level (standalone.yaml and cluster.yaml)**:
- Password received as template variable `${admin_password}` (lines 90 and 122)
- Used directly in neo4j-admin command to set initial database password
- Executed during VM first boot in plain text command

**Deployment Tooling Level (deployments/src/)**:
- PasswordManager class already supports four strategies: GENERATE, ENVIRONMENT, AZURE_KEYVAULT, PROMPT
- Basic Key Vault retrieval already implemented for deployment orchestration
- Retrieves secret named "neo4j-admin-password" from configured vault
- Passwords written to temporary parameter JSON files on disk

**Azure Marketplace Level (createUiDefinition.json)**:
- Interactive password input field with validation (lines 8-23)
- Complexity requirements enforced: twelve to seventy two characters with three of four character types
- Password transmitted as secure parameter to template deployment

### 1.2 Security Limitations of Current Approach

**Deployment History Exposure**:
- Azure stores deployment metadata including parameter values
- Even with `@secure()`, parameters may appear in deployment history
- Cloud-init customData is base64-encoded but visible in VM metadata

**Local File Storage**:
- Deployment tools write passwords to parameter JSON files
- Files stored in `.arm-testing/params/` directory
- Temporary files may persist on developer machines

**No Centralized Secret Management**:
- Each deployment has isolated password with no central repository
- No unified rotation capability across deployments
- No centralized audit trail of password access

**Limited Access Control**:
- Password known by deployment initiator
- No granular RBAC for password access
- No separation between deployment permission and password knowledge

**Credential Lifecycle Gaps**:
- No built-in password rotation mechanism
- Password change requires redeployment or manual intervention
- No expiration policies enforced

**Audit Trail Limitations**:
- No centralized logging of who accessed passwords
- No tracking of password usage beyond deployment logs
- Compliance reporting requires manual correlation

### 1.3 Existing Key Vault Support in Deployment Tools

The deployment framework already includes partial Key Vault integration:

**PasswordManager Implementation (password.py lines 126-173)**:
- Retrieves password from Azure Key Vault using Azure CLI
- Expects vault name in settings configuration
- Retrieves secret named "neo4j-admin-password"
- Provides helpful error messages for common issues

**Current Scope Limitation**:
- Key Vault integration only in deployment orchestration layer
- Bicep templates still require password as direct parameter
- Cloud-init still receives password in embedded form
- No VM runtime Key Vault retrieval

## 2. Proposed Architecture

### 2.1 Design Principles

**Security First**:
- Secrets never written to disk in plain text
- Secrets never visible in deployment history or logs
- Secrets retrieved just-in-time by VMs using Managed Identity
- All secret access audited in Key Vault logs

**Backward Compatibility**:
- Existing deployments continue to work without modification
- Gradual migration path from parameter-based to vault-based
- Support both deployment patterns during transition
- No breaking changes to existing templates

**Marketplace Compatibility**:
- Simple path for new Marketplace users without existing infrastructure
- Enterprise path for users with existing Key Vault
- Template can auto-create vault when needed
- Compliant with Azure Marketplace certification requirements

**Operational Simplicity**:
- Minimal changes to deployment workflow
- Clear migration documentation
- Automated setup where possible
- Graceful fallbacks for transition period

**Enterprise Ready**:
- Integration with existing Azure governance
- Support for RBAC and Azure Policy
- Centralized secret lifecycle management
- Comprehensive audit capabilities

### 2.2 Key Vault Integration Patterns

**Pattern A: User-Managed Key Vault (Recommended for Direct Deployments)**

Flow:
1. User or automation creates Key Vault before deployment
2. User or script generates secure password and stores as secret
3. Bicep template receives Key Vault resource ID and secret name as parameters
4. Bicep grants VM Managed Identity access to Key Vault
5. Cloud-init script uses Managed Identity to retrieve password at runtime
6. Password used to initialize Neo4j without ever appearing in template

Advantages:
- User maintains full control of Key Vault lifecycle
- Vault can be shared across multiple deployments
- Centralized secret management for organization
- Works with existing enterprise Key Vault infrastructure

Disadvantages:
- Requires pre-deployment setup steps
- More complex for first-time users
- User responsible for vault permissions and networking

**Pattern B: Template-Managed Key Vault (Recommended for Marketplace)**

Flow:
1. User initiates deployment via Marketplace or CLI
2. Bicep template creates new Key Vault as part of deployment
3. Bicep generates password using deployment script or unique string formula
4. Bicep stores password in vault as secret
5. Bicep grants VM Managed Identity access to vault
6. Cloud-init retrieves password from vault at runtime
7. Deployment outputs include vault name and secret name (not password)

Advantages:
- Zero pre-deployment setup required
- Simple user experience for Marketplace
- Vault lifecycle tied to deployment
- Automatic permission configuration

Disadvantages:
- Each deployment creates separate vault (cost and management overhead)
- Password generation in template has complexity constraints
- Vault deletion must be handled carefully (soft delete, purge protection)

**Pattern C: Hybrid Approach (Recommended for Production)**

Flow:
1. Bicep template accepts parameter: `keyVaultMode` with values "existing", "create", or "parameter"
2. If "existing": user provides vault resource ID and secret name
3. If "create": template creates vault and generates password
4. If "parameter": fallback to current behavior for backward compatibility
5. Cloud-init logic detects mode and retrieves password accordingly

Advantages:
- Supports all deployment scenarios
- Smooth migration path
- Marketplace and enterprise both supported
- Backward compatible during transition

Disadvantages:
- More complex template logic
- More testing scenarios required
- Need to maintain multiple code paths

### 2.3 VM Password Retrieval Mechanism

**Cloud-Init Approach (Recommended)**

Modify cloud-init YAML to include Key Vault retrieval logic:

Process:
1. VM boots with Managed Identity assigned
2. Cloud-init script detects Key Vault mode from template variables
3. Script uses Azure Instance Metadata Service to get access token
4. Script calls Key Vault REST API to retrieve secret
5. Secret used in memory to set Neo4j password
6. Secret never written to disk or logs

Implementation considerations:
- Requires curl and jq available in VM image (already present)
- Must wait for Managed Identity propagation (may need retry loop)
- Error handling for vault access failures
- Fallback mechanism during transition period

**VM Extension Approach (Alternative)**

Use Azure VM Custom Script Extension instead of cloud-init:

Process:
1. Bicep deploys VMs without Neo4j configured
2. Separate VM extension retrieves password from vault
3. Extension configures Neo4j with password
4. Extension reports success or failure

Advantages:
- Cleaner separation of infrastructure and configuration
- Better error reporting through extension status
- Can run after VM fully provisioned

Disadvantages:
- More complex template structure
- Slower deployment due to sequential operations
- Read replica legacy script still uses extensions (conflict potential)

**Recommendation**: Use cloud-init approach for consistency with current architecture and faster deployment times.

### 2.4 Password Generation Strategy

**Option 1: Deployment Script Generation (Recommended for Phase 1)**

Process:
- Deployment script (deploy.sh or Python tool) generates secure password
- Script creates or updates Key Vault secret before deployment
- Script passes vault reference to Bicep (not password)
- Bicep template retrieves using reference function if needed

Advantages:
- Full control over password complexity
- Can use cryptographically secure random generators
- Works with existing deployment tooling
- No changes to Bicep template for generation

**Option 2: Bicep Native Generation (Recommended for Marketplace)**

Process:
- Bicep uses deployment script resource to generate password
- Password stored directly in vault from template
- Deployment output includes vault reference only

Challenges:
- Bicep deployment scripts have limitations
- Complex to implement proper password complexity
- Requires careful handling of deployment script outputs
- May expose password in deployment logs if not careful

**Option 3: Azure Function Generation (Enterprise Option)**

Process:
- Bicep triggers Azure Function via deployment script
- Function generates password with full complexity
- Function stores in vault and returns reference
- Bicep uses reference for VM configuration

Advantages:
- Most flexible password generation
- Can integrate with enterprise password policies
- Centralized generation logic
- Full audit trail

Disadvantages:
- Requires Function App infrastructure
- More complex deployment dependencies
- Higher cost for simple deployments
- Not suitable for Marketplace without pre-existing function

**Recommendation**: Use Option 1 for direct deployments, Option 2 for Marketplace once tested thoroughly.

## 3. Implementation Phases

### Phase 1: Foundation and Backward Compatibility

**Objective**: Add Key Vault support without breaking existing deployments.

**Scope**:
- Add optional Key Vault parameters to Bicep template
- Maintain existing adminPassword parameter with default behavior
- Update deployment scripts to support vault creation and secret storage
- Create comprehensive documentation for vault setup
- Add validation and testing for both modes

**Bicep Template Changes**:
- Add new optional parameters: useKeyVault (boolean), keyVaultName (string), keyVaultResourceGroup (string), passwordSecretName (string)
- Add conditional logic: if useKeyVault is false, use existing adminPassword parameter
- Add Managed Identity permissions to access vault when enabled
- Update cloud-init variable substitution to support vault mode
- Maintain full backward compatibility with existing parameter files

**Cloud-Init Changes**:
- Add template variables: USE_KEY_VAULT, VAULT_NAME, SECRET_NAME
- Add conditional logic at password retrieval section
- If vault mode: retrieve password using Managed Identity and Azure REST API
- If parameter mode: use existing embedded password variable
- Add retry logic for Managed Identity propagation delays
- Add error logging for vault access failures

**Deployment Script Changes (deploy.sh)**:
- Add optional flags: --use-vault, --vault-name, --generate-password
- If vault mode: generate password and store in vault before deployment
- Pass vault parameters to Bicep instead of password
- Add vault creation logic if vault does not exist
- Add secret creation with proper permissions
- Validate vault access before deployment

**Deployment Tool Changes (deployments/src/)**:
- Extend existing PasswordManager Key Vault support
- Add vault creation capability if not exists
- Generate and store password in vault before parameter file generation
- Remove password from parameter file when vault mode enabled
- Add vault name and secret name to parameter file instead
- Update validation logic for vault-based deployments

**Testing Requirements**:
- Test backward compatibility: existing deployments with password parameter
- Test vault mode: new deployments with user-managed vault
- Test vault creation: new deployments with auto-created vault
- Test Managed Identity: verify VM can access vault
- Test error handling: vault access failures, network issues, permission problems
- Test both standalone and cluster deployments
- Test with different Azure regions and subscription types

**Documentation**:
- Migration guide from password-based to vault-based
- Step-by-step vault setup instructions
- Troubleshooting guide for common vault access issues
- Security best practices document
- Architecture decision record for vault integration

**Success Criteria**:
- Zero breaking changes to existing deployments
- New vault-based deployments succeed in test environments
- Documentation complete and peer-reviewed
- All tests passing for both modes

**Timeline Estimate**: Foundation phase suitable for immediate implementation after proposal approval.

### Phase 2: Cloud-Init Vault Retrieval

**Objective**: Enable VMs to retrieve passwords from Key Vault at runtime without password in template.

**Scope**:
- Implement robust vault retrieval logic in cloud-init
- Handle Managed Identity authentication
- Add comprehensive error handling and retry logic
- Ensure no passwords in deployment metadata
- Validate across all deployment scenarios

**Cloud-Init Implementation Details**:

Add vault retrieval function to both standalone.yaml and cluster.yaml:

Step 1: Obtain Managed Identity access token
- Use Azure Instance Metadata Service endpoint
- Request token for Key Vault resource
- Handle token refresh for long-running operations
- Add retry logic for identity propagation delays (up to two minutes)

Step 2: Retrieve secret from Key Vault
- Call Key Vault REST API with access token
- Parse JSON response to extract secret value
- Validate secret meets password requirements
- Handle vault access errors with clear messages

Step 3: Use password for Neo4j initialization
- Store password in memory variable only (never disk)
- Execute neo4j-admin set-initial-password with variable
- Clear password variable after use
- Verify Neo4j started successfully with password

Error Handling:
- Managed Identity not ready: retry up to ten times with exponential backoff
- Vault not accessible: check network, permissions, vault existence
- Secret not found: verify secret name, check permissions
- Invalid password: validate complexity before use
- Log all errors to cloud-init log for troubleshooting

**Template Variable Additions**:
- USE_KEY_VAULT: boolean flag to enable vault retrieval
- VAULT_NAME: name of Key Vault containing password
- SECRET_NAME: name of secret within vault (default: neo4j-admin-password)
- VAULT_URI: full URI to vault (constructed from vault name)

**Bicep Changes**:
- Replace password string substitution with vault metadata
- Pass vault configuration variables to cloud-init
- Remove password from cloud-init data entirely in vault mode
- Ensure Managed Identity assigned before VM boots
- Grant Managed Identity "Key Vault Secrets User" role
- Add RBAC role assignment with proper retry for propagation

**Managed Identity Configuration**:
- User-assigned Managed Identity created by template
- Identity granted access to Key Vault before VM creation
- Role assignment: "Key Vault Secrets User" (least privilege)
- Scope: specific to password secret only if possible
- Add delay between role assignment and VM creation for propagation

**Testing Requirements**:
- Test Managed Identity authentication across regions
- Test vault retrieval with various network configurations
- Test error scenarios: missing vault, missing secret, no permissions
- Test concurrent deployments sharing same vault
- Test cluster deployments where all nodes retrieve same secret
- Verify no password in deployment history or VM metadata
- Performance test: vault retrieval should not significantly delay boot

**Migration Path**:
- Update documentation to recommend vault mode
- Provide migration scripts for existing deployments
- Add warnings to password parameter about deprecation
- Create automated migration tool for bulk updates

**Success Criteria**:
- VMs successfully retrieve passwords from vault in all scenarios
- Zero password exposure in deployment metadata
- Error messages provide clear guidance for troubleshooting
- Performance impact minimal (less than thirty seconds added to boot time)
- Migration documentation complete with examples

**Timeline Estimate**: Can proceed immediately after Phase 1 completion and testing.

### Phase 3: Marketplace Integration

**Objective**: Integrate Key Vault into Azure Marketplace offering with simple user experience.

**Scope**:
- Update createUiDefinition.json to offer vault options
- Add template auto-vault-creation capability
- Provide simple path for new users and enterprise path for existing vault users
- Ensure Marketplace certification compliance
- Update marketplace documentation and screenshots

**createUiDefinition.json Changes**:

Add new configuration step "Security Settings":

Field 1: Password Management Mode (dropdown)
- Option A: Auto-create Key Vault (recommended for new deployments)
- Option B: Use existing Key Vault (recommended for enterprise)
- Option C: Direct password input (legacy, not recommended)

Field 2: Key Vault Name (if Option A selected)
- Auto-generated default based on deployment name
- User can override
- Validation: unique within subscription, valid naming convention

Field 3: Existing Key Vault (if Option B selected)
- Resource picker for existing Key Vault
- Validation: vault exists, user has access
- Secret name input (default: neo4j-admin-password)

Field 4: Password Input (if Option C selected)
- Existing password field with validation
- Warning message: "For enhanced security, use Key Vault option"

**Template Auto-Creation Logic**:

When user selects "Auto-create Key Vault":
1. Bicep creates Key Vault resource with unique name
2. Enable soft delete and purge protection for compliance
3. Configure network access rules (default: allow Azure services)
4. Generate password using deployment script
5. Store password as secret in vault
6. Grant Managed Identity access to vault
7. Configure VMs to retrieve from vault
8. Output vault name and secret name (not password)

Key Vault Configuration Best Practices:
- Enable Azure RBAC for permissions (not access policies)
- Enable soft delete with ninety day retention
- Enable purge protection to prevent accidental deletion
- Add deployment tags for lifecycle management
- Configure diagnostic settings for audit logs
- Apply network restrictions based on user preference

**Password Generation in Template**:

Use Bicep deployment script with PowerShell or Bash:
- Generate cryptographically secure random password
- Ensure complexity: twelve characters minimum, all four character types
- Store in vault immediately after generation
- Return only vault reference, never password value
- Handle idempotency for redeployments

**Marketplace Certification Considerations**:
- No external dependencies allowed in Marketplace offers
- All resources must be created within template
- Outputs must not expose secrets
- Must support both new and existing vault scenarios
- Must handle all Azure regions
- Must work with government cloud and sovereign clouds

**Documentation Updates**:
- Update Marketplace listing description to highlight Key Vault security
- Create deployment guide showing both simple and enterprise paths
- Add architecture diagrams for each vault mode
- Update screenshots showing new UI options
- Create video walkthrough for Marketplace deployment

**Testing Requirements**:
- Test Marketplace deployment with auto-create vault option
- Test Marketplace deployment with existing vault option
- Test backward compatibility with direct password
- Validate across multiple Azure regions
- Test with different subscription types (EA, CSP, pay-as-you-go)
- Verify outputs contain vault reference only
- Confirm secrets not exposed in any deployment metadata
- Test cleanup and redeployment scenarios

**Success Criteria**:
- Marketplace deployment succeeds with vault mode in all regions
- User experience simple for new deployments
- Enterprise users can integrate with existing vaults
- Zero secret exposure in any deployment output
- Marketplace certification passes all security scans
- Documentation approved by technical review

**Timeline Estimate**: Begin after Phase 2 proven stable; coordinate with Marketplace team for certification timeline.

### Phase 4: Deprecation and Mandatory Key Vault

**Objective**: Complete transition to Key Vault as the only supported password mechanism.

**Scope**:
- Deprecate direct password parameter
- Make Key Vault mandatory for all new deployments
- Provide migration tools for existing deployments
- Implement full audit trail and compliance reporting
- Clean up legacy code paths

**Deprecation Process**:

Month 1-3: Warning Period
- Add prominent warnings to documentation about upcoming deprecation
- Update all parameter files with vault references
- Add runtime warnings when password parameter used
- Publish migration guide with automated tools
- Notify existing customers via email and portal notifications

Month 4-6: Soft Deprecation
- Password parameter marked as deprecated in template
- Deployment shows warning message but continues to work
- New deployments default to vault mode
- Marketplace UI removes direct password option
- Add telemetry to track remaining password-based deployments

Month 7-9: Hard Deprecation
- Remove password parameter from template
- Deployments without vault reference fail with clear error message
- Provide emergency override for critical situations
- Publish final migration deadline announcement

Month 10-12: Removal
- Completely remove password parameter and related code
- Clean up conditional logic from cloud-init
- Simplify template structure
- Update all documentation to vault-only approach

**Migration Tooling**:

Automated Migration Script:
- Scan existing deployments for password-based configurations
- Generate vault and secrets for each deployment
- Update parameter files to reference vault
- Validate migrated deployments
- Generate migration report

Bulk Migration Tool:
- Support for migrating multiple deployments simultaneously
- Integration with Azure Resource Graph for discovery
- Validation and rollback capabilities
- Progress tracking and error reporting

**Audit Trail Implementation**:

Enable comprehensive secret access logging:
- Configure Key Vault diagnostic settings to send logs to Log Analytics
- Create Azure Monitor workbook for password access visualization
- Set up alerts for unusual access patterns
- Integrate with Azure Sentinel for security analysis
- Create compliance reports for audit requirements

Implement secret rotation:
- Create automation to rotate Neo4j passwords on schedule
- Use Azure Automation or Logic Apps for rotation workflow
- Update Key Vault secret with new password
- Trigger Neo4j password change via API
- Validate rotation success and alert on failures

**Compliance and Governance**:

Azure Policy Integration:
- Create policy requiring Key Vault for Neo4j deployments
- Audit existing deployments for compliance
- Prevent creation of non-vault deployments
- Generate compliance reports for security teams

RBAC Best Practices:
- Document recommended RBAC configurations
- Separate vault administration from deployment permissions
- Implement least privilege access patterns
- Regular access reviews and permission audits

**Code Cleanup**:
- Remove all password parameter references
- Simplify cloud-init logic to vault-only path
- Remove conditional vault mode checks
- Update all tests to vault-only scenarios
- Archive legacy deployment scripts

**Success Criteria**:
- Zero active deployments using password parameter
- All existing deployments migrated to vault
- Comprehensive audit trail operational
- Compliance reports available for security teams
- Code simplified with legacy paths removed
- Documentation updated and complete

**Timeline Estimate**: Begin deprecation cycle after Phase 3 deployed to production and stable for at least six months.

## 4. Technical Implementation Details

### 4.1 Bicep Template Modifications

**New Parameters to Add**:

```
Parameter: useKeyVault
Type: boolean
Default: false (Phase 1), true (Phase 4)
Description: Enable Azure Key Vault for password management

Parameter: keyVaultResourceGroup
Type: string
Default: resourceGroup().name
Description: Resource group containing the Key Vault

Parameter: keyVaultName
Type: string
Default: empty string
Description: Name of existing Key Vault or name for new vault

Parameter: createKeyVault
Type: boolean
Default: false
Description: Create new Key Vault as part of deployment

Parameter: passwordSecretName
Type: string
Default: 'neo4j-admin-password'
Description: Name of secret in Key Vault containing Neo4j password

Parameter: keyVaultAccessPolicies
Type: array
Default: []
Description: Additional access policies for Key Vault (enterprise scenarios)
```

**Managed Identity RBAC Assignment**:

```
Resource: roleAssignment
Type: Microsoft.Authorization/roleAssignments
Condition: useKeyVault == true
Properties:
  - roleDefinitionId: Key Vault Secrets User role ID
  - principalId: userAssignedIdentity.properties.principalId
  - scope: Key Vault resource ID
  - principalType: ServicePrincipal
```

**Key Vault Creation (Optional)**:

```
Resource: keyVault
Type: Microsoft.KeyVault/vaults
Condition: createKeyVault == true
Properties:
  - enableRbacAuthorization: true
  - enableSoftDelete: true
  - softDeleteRetentionInDays: 90
  - enablePurgeProtection: true
  - networkAcls: allow Azure services
  - sku: standard
  - tags: deployment metadata
```

**Cloud-Init Variable Updates**:

Replace direct password substitution with vault metadata:

```
Current approach:
  cloudInitData = replace(template, '${admin_password}', adminPassword)

New approach when useKeyVault:
  cloudInitData = replace(
    replace(
      replace(template, '${use_key_vault}', 'true'),
      '${vault_name}', keyVaultName
    ),
    '${secret_name}', passwordSecretName
  )
```

### 4.2 Cloud-Init YAML Modifications

**Add Vault Retrieval Section** (before Neo4j password configuration):

```
Section: Retrieve password from Key Vault

Step 1: Wait for Managed Identity propagation
  - Retry loop up to ten times with five second delays
  - Test identity by requesting access token
  - Exit with error if identity not available after maximum retries

Step 2: Obtain access token for Key Vault
  - Call Azure Instance Metadata Service endpoint
  - Request token for https://vault.azure.net resource
  - Extract access token from JSON response
  - Validate token received successfully

Step 3: Retrieve secret from Key Vault
  - Construct vault URL from vault name
  - Call Key Vault REST API with access token
  - Parse secret value from JSON response
  - Validate password meets complexity requirements

Step 4: Store password in memory variable
  - Export PASSWORD variable for use in subsequent commands
  - Never write password to disk or logs
  - Use password only in neo4j-admin command

Step 5: Error handling
  - Log all vault access attempts to cloud-init log
  - Provide clear error messages for each failure type
  - Suggest remediation steps in error messages
  - Exit with non-zero code on failure for visibility
```

**Updated Neo4j Password Initialization**:

```
Current line:
  - neo4j-admin dbms set-initial-password '${admin_password}'

New conditional logic:
  - |
    if [ "${use_key_vault}" = "true" ]; then
      # Password already retrieved and stored in $PASSWORD variable
      neo4j-admin dbms set-initial-password "$PASSWORD"
      unset PASSWORD  # Clear from memory
    else
      # Legacy parameter-based password (Phase 1-3 only)
      neo4j-admin dbms set-initial-password '${admin_password}'
    fi
```

### 4.3 Deployment Script Enhancements

**deploy.sh Updates**:

```
Add command-line options:
  --use-vault: Enable Key Vault mode
  --vault-name: Specify Key Vault name
  --create-vault: Create new Key Vault
  --vault-resource-group: Vault resource group (default: deployment RG)
  --generate-password: Generate secure password automatically

Pre-deployment vault setup:
  1. If --create-vault specified:
     - Create Key Vault with unique name
     - Enable RBAC, soft delete, purge protection
     - Apply tags for lifecycle management

  2. If --generate-password specified:
     - Generate cryptographically secure password
     - Ensure complexity requirements met
     - Store in vault as secret
     - Validate secret created successfully

  3. Update parameter file:
     - Remove adminPassword parameter
     - Add useKeyVault: true
     - Add keyVaultName, passwordSecretName
     - Validate parameter file structure

Deployment execution:
  - Pass vault parameters to Bicep
  - Monitor deployment for vault-related errors
  - Validate Managed Identity permissions
  - Verify VMs can access vault post-deployment

Post-deployment validation:
  - Test secret retrieval using VM Managed Identity
  - Verify Neo4j started successfully
  - Check cloud-init logs for vault access
  - Output vault reference for documentation
```

**Python Deployment Tool Updates** (deployments/src/deployment.py):

```
Enhance PasswordManager integration:
  - When vault strategy selected, create vault if needed
  - Generate password and store in vault
  - Validate vault permissions before deployment
  - Remove password from parameter file generation
  - Add vault metadata to parameter file instead

Update parameter file generation:
  - Skip adminPassword parameter when vault mode
  - Add vault-specific parameters
  - Validate vault exists and accessible
  - Store vault reference in deployment state

Enhance deployment orchestration:
  - Verify vault access before starting deployment
  - Monitor vault access during VM provisioning
  - Validate secret retrieval in post-deployment checks
  - Include vault information in deployment reports
```

### 4.4 Error Handling and Resilience

**Managed Identity Propagation**:

Challenge: Role assignment propagation can take up to two minutes
Solution: Implement exponential backoff retry logic in cloud-init

```
Retry strategy:
  - Initial wait: five seconds after VM boot
  - Retry interval: exponential backoff (5, 10, 20, 40 seconds)
  - Maximum retries: ten attempts (approximately three minutes total)
  - Success: proceed with password retrieval
  - Failure: log detailed error and exit with non-zero code

Logging:
  - Log each retry attempt with timestamp
  - Log Managed Identity status responses
  - Log final success or failure clearly
  - Include correlation ID for Azure support
```

**Key Vault Access Failures**:

Common failure scenarios and handling:

```
Scenario 1: Vault does not exist
  - Error message: "Key Vault '{name}' not found in resource group '{rg}'"
  - Remediation: Verify vault name, check vault was created
  - Exit code: 101

Scenario 2: Secret does not exist
  - Error message: "Secret '{secret}' not found in vault '{vault}'"
  - Remediation: Verify secret name, check secret was created
  - Exit code: 102

Scenario 3: No permission to access vault
  - Error message: "Access denied to vault '{vault}'. Verify Managed Identity has 'Key Vault Secrets User' role"
  - Remediation: Check RBAC role assignments, verify identity is correct
  - Exit code: 103

Scenario 4: Network access blocked
  - Error message: "Cannot reach vault '{vault}'. Check network configuration and firewall rules"
  - Remediation: Verify vault network settings, check VM network connectivity
  - Exit code: 104

Scenario 5: Invalid password retrieved
  - Error message: "Password from vault does not meet Neo4j complexity requirements"
  - Remediation: Regenerate password with proper complexity
  - Exit code: 105
```

**Validation and Health Checks**:

```
Pre-deployment validation:
  - Verify vault exists and accessible from deployment machine
  - Validate secret exists with non-empty value
  - Test Managed Identity can authenticate
  - Verify RBAC roles assigned correctly

Post-deployment validation:
  - Query cloud-init logs for successful vault access
  - Attempt to authenticate to Neo4j with retrieved password
  - Verify no passwords in deployment outputs or metadata
  - Check Key Vault audit logs for access events

Continuous monitoring:
  - Alert on failed vault access attempts
  - Monitor Managed Identity token refresh
  - Track secret rotation events
  - Audit unusual access patterns
```

## 5. Security Considerations

### 5.1 Threat Model Analysis

**Threat: Deployment History Exposure**

Current Risk: Passwords visible in Azure deployment history even with @secure() decorator

Mitigation:
- Use Key Vault references instead of password values
- Vault resource ID and secret name are not sensitive
- Deployment history shows vault reference only
- Password never appears in any deployment metadata

Residual Risk: Minimal - vault name and secret name exposure has low security impact

**Threat: Cloud-Init Data Inspection**

Current Risk: customData is base64-encoded but can be decoded from VM metadata service

Mitigation:
- Remove password from customData entirely
- Pass only vault reference in customData
- Vault retrieval logic executed in cloud-init
- Password exists only in memory during initialization

Residual Risk: Minimal - vault metadata exposure has low impact

**Threat: Local Parameter File Exposure**

Current Risk: Parameter JSON files on developer machines contain passwords

Mitigation:
- Remove password from parameter files when vault mode enabled
- Only vault reference stored in parameter files
- Deployment tools store vault metadata instead of secrets
- Git ignore patterns prevent accidental commit

Residual Risk: Minimal - parameter files no longer contain sensitive data

**Threat: Unauthorized Vault Access**

Current Risk: Attacker with access to Managed Identity could retrieve password

Mitigation:
- Managed Identity scoped to specific secret only
- Key Vault RBAC provides granular access control
- Audit logs track all secret access attempts
- Network restrictions limit vault access surface
- Conditional access policies can be applied

Residual Risk: Medium - compromised VM can still access its own password (acceptable for initialization)

**Threat: Password Interception During Retrieval**

Current Risk: Password transmitted from vault to VM could be intercepted

Mitigation:
- All vault communication over TLS (HTTPS)
- Azure backbone network for vault connectivity
- Managed Identity token-based authentication
- No password transmission outside Azure network
- Short-lived access tokens reduce exposure window

Residual Risk: Low - Azure network security provides strong protection

**Threat: Vault Deletion or Secret Deletion**

Current Risk: Accidental deletion breaks running deployments

Mitigation:
- Enable soft delete with ninety day retention
- Enable purge protection to prevent immediate purge
- Tag vaults with deployment metadata for lifecycle management
- Azure Policy can prevent deletion of tagged vaults
- Backup critical secrets to secondary vault

Residual Risk: Low - soft delete and purge protection provide recovery window

### 5.2 Compliance and Governance

**Audit Trail Requirements**:

```
Key Vault Diagnostic Settings:
  - Enable audit logging for all secret operations
  - Send logs to Log Analytics workspace
  - Retain logs for minimum one year (configurable)
  - Include: who accessed, when, from where, success or failure

Log Analytics Queries:
  - Track all secret read operations
  - Identify unusual access patterns
  - Correlate access with deployment events
  - Generate compliance reports

Alert Configuration:
  - Alert on failed access attempts
  - Alert on access from unexpected locations
  - Alert on secret modifications
  - Alert on vault configuration changes
```

**Regulatory Compliance**:

```
GDPR Considerations:
  - Passwords are not personal data but protect access to data
  - Audit logs may contain user identities (compliant)
  - Data residency requirements met by vault location
  - Right to be forgotten handled via secret rotation

PCI-DSS Considerations:
  - Requirement 8.2: Unique IDs and strong authentication
  - Requirement 8.3: Multi-factor authentication (Managed Identity)
  - Requirement 10.2: Audit trails for all access
  - Requirement 10.3: Tamper-evident audit trails

HIPAA Considerations:
  - Administrative safeguards: access controls via RBAC
  - Technical safeguards: encryption in transit and at rest
  - Audit controls: comprehensive logging
  - Integrity controls: tamper protection via Azure platform

SOC 2 Considerations:
  - CC6.1: Logical access security
  - CC6.6: Encryption of confidential data
  - CC7.2: System monitoring
  - CC7.3: Evaluation and management of changes
```

**Azure Policy Integration**:

```
Policy 1: Require Key Vault for Neo4j Deployments
  - Effect: Deny deployments without vault reference
  - Scope: Specific resource groups or subscriptions
  - Compliance: Audit non-compliant deployments

Policy 2: Enforce Key Vault Configuration
  - Require RBAC authorization model
  - Require soft delete enabled
  - Require purge protection enabled
  - Require diagnostic settings configured

Policy 3: Managed Identity Requirements
  - Require user-assigned identity for VMs
  - Deny system-assigned identities (organization preference)
  - Require specific naming convention for identities

Policy 4: Network Security
  - Require private endpoints for vaults (optional)
  - Deny public network access (optional)
  - Require specific virtual network integration
```

### 5.3 Secret Lifecycle Management

**Password Rotation Strategy**:

```
Automated Rotation:
  - Schedule: quarterly or based on compliance requirements
  - Trigger: Azure Automation runbook or Logic App
  - Process:
    1. Generate new secure password
    2. Update Neo4j database password via Cypher
    3. Update Key Vault secret with new password
    4. Validate new password works
    5. Notify administrators of rotation

Manual Rotation:
  - Documented procedure for emergency rotation
  - Requires specific RBAC permissions
  - Includes validation steps
  - Audit trail recorded

Rotation Validation:
  - Test new password against Neo4j before finalizing
  - Rollback capability if validation fails
  - Alert on rotation failures
  - Document all rotation events
```

**Secret Expiration**:

```
Key Vault Secret Properties:
  - Set expiration date on secrets (optional)
  - Configure alerts before expiration
  - Automate renewal process
  - Track expiration in compliance reports

Handling Expired Secrets:
  - Prevent Neo4j startup if secret expired
  - Clear error message with remediation steps
  - Automated alert to administrators
  - Documented emergency access procedure
```

**Disaster Recovery**:

```
Backup Strategy:
  - Export critical secrets to secondary vault in different region
  - Store backup vault reference in deployment documentation
  - Test recovery procedure quarterly
  - Document recovery RTO and RPO

Recovery Procedure:
  1. Identify failed vault or lost secret
  2. Restore from backup vault or soft delete
  3. Update deployment references to backup vault
  4. Validate Neo4j can access backup secret
  5. Document recovery event
```

## 6. Migration Strategy

### 6.1 Migration Paths

**Path 1: New Deployments**

Target: All new deployments starting from Phase 1 completion

```
Recommended approach:
  - Use Key Vault mode from initial deployment
  - Auto-create vault or use existing enterprise vault
  - Never use direct password parameter
  - Follow vault best practices from start

Migration steps:
  1. Choose vault strategy (create or existing)
  2. Run deployment with --use-vault flag
  3. Validate successful vault retrieval
  4. Document vault reference for operations
```

**Path 2: Existing Standalone Deployments**

Target: Existing single-node Neo4j instances

```
Migration approach:
  1. Create Key Vault for deployment
  2. Retrieve current password from Neo4j
  3. Store current password in vault as secret
  4. Update deployment parameters to reference vault
  5. Redeploy with vault mode enabled
  6. Validate Neo4j still accessible with same password

Alternative approach (with password change):
  1. Create Key Vault with new password
  2. Update deployment to use vault
  3. After successful deployment, use Neo4j to change password
  4. Validate new password stored in vault
```

**Path 3: Existing Cluster Deployments**

Target: Multi-node Neo4j clusters

```
Migration approach:
  1. Create Key Vault for cluster
  2. Store current cluster password in vault
  3. Update deployment parameters for all nodes
  4. Rolling restart nodes to pick up vault configuration
  5. Validate cluster health after migration

Considerations:
  - Minimize downtime during migration
  - Maintain cluster quorum throughout process
  - Validate cluster replication after migration
  - Test failover scenarios post-migration
```

### 6.2 Automated Migration Tooling

**Migration Assessment Tool**:

```
Purpose: Identify deployments requiring migration

Functionality:
  - Query Azure Resource Graph for Neo4j deployments
  - Identify deployments using password parameter
  - Assess complexity of each deployment
  - Generate migration priority report
  - Estimate migration effort and risk

Output:
  - List of deployments to migrate
  - Recommended migration path for each
  - Risk assessment (low, medium, high)
  - Timeline estimate
```

**Automated Migration Script**:

```
Purpose: Automate migration process where possible

Functionality:
  - Create Key Vault for deployment
  - Generate or import password
  - Update parameter files
  - Validate vault configuration
  - Generate migration report

Usage:
  ./migrate-to-vault.sh <deployment-name> [options]

Options:
  --vault-name: Specify vault name (default: auto-generate)
  --existing-vault: Use existing vault
  --preserve-password: Keep current password
  --generate-new-password: Generate new password
  --validate-only: Test migration without executing
  --rollback: Rollback to previous configuration
```

### 6.3 Rollback Procedures

**Pre-Migration Backup**:

```
Before migration:
  - Document current deployment configuration
  - Export current parameter files
  - Record current passwords securely
  - Backup Neo4j database
  - Create deployment snapshot
```

**Rollback Triggers**:

```
Rollback if:
  - Vault access fails during deployment
  - Neo4j fails to start with vault password
  - Cluster health degraded after migration
  - Unexpected errors in cloud-init logs
  - Validation tests fail
```

**Rollback Procedure**:

```
Steps:
  1. Stop failed deployment
  2. Restore previous parameter files
  3. Redeploy with password parameter mode
  4. Validate Neo4j accessible
  5. Document rollback reason
  6. Review and fix issue before retry

Validation:
  - Confirm Neo4j responding to queries
  - Verify cluster health if applicable
  - Check no data loss occurred
  - Review logs for root cause
```

## 7. Testing Strategy

### 7.1 Test Scenarios

**Functional Testing**:

```
Test 1: Vault Creation and Deployment
  - Create new vault via template
  - Generate password automatically
  - Deploy standalone Neo4j instance
  - Validate password retrieval successful
  - Confirm Neo4j accessible

Test 2: Existing Vault Usage
  - Use pre-existing vault
  - Deploy with vault reference
  - Validate Managed Identity permissions
  - Confirm password retrieval
  - Verify Neo4j initialization

Test 3: Cluster Deployment with Vault
  - Deploy three node cluster
  - All nodes retrieve from same vault
  - Validate cluster formation
  - Test cluster operations
  - Verify high availability

Test 4: Read Replica with Vault (4.4 only)
  - Deploy cluster with read replicas
  - Replicas use same vault
  - Validate replica connectivity
  - Test read scaling
  - Verify replication

Test 5: Marketplace Deployment
  - Deploy via Marketplace UI
  - Test auto-create vault option
  - Test existing vault option
  - Validate outputs
  - Verify no secret exposure

Test 6: Backward Compatibility
  - Deploy with password parameter (legacy mode)
  - Validate deployment succeeds
  - Confirm deprecation warnings shown
  - Verify migration path documented
```

**Security Testing**:

```
Test 7: Secret Exposure Verification
  - Review deployment outputs for secrets
  - Check deployment history
  - Inspect VM metadata
  - Query cloud-init logs
  - Confirm zero secret exposure

Test 8: Managed Identity Validation
  - Verify correct identity assigned
  - Validate RBAC role assignments
  - Test identity can access vault
  - Confirm identity cannot access other vaults
  - Test identity isolation

Test 9: Network Security
  - Test vault with private endpoint
  - Validate network restrictions
  - Confirm firewall rules work
  - Test from different virtual networks
  - Verify Azure backbone connectivity

Test 10: Audit Trail Verification
  - Generate vault access events
  - Query Key Vault logs
  - Validate log completeness
  - Test alert triggers
  - Verify compliance reports
```

**Failure Testing**:

```
Test 11: Vault Not Accessible
  - Simulate vault network failure
  - Verify error handling
  - Confirm clear error messages
  - Test retry logic
  - Validate deployment fails gracefully

Test 12: Secret Missing
  - Deploy with non-existent secret
  - Verify error detection
  - Confirm helpful error message
  - Test does not expose other secrets
  - Validate cleanup on failure

Test 13: Permission Denied
  - Remove Managed Identity permissions
  - Attempt deployment
  - Verify access denied error
  - Confirm remediation guidance
  - Test does not proceed without access

Test 14: Managed Identity Propagation Delay
  - Deploy immediately after role assignment
  - Verify retry logic works
  - Confirm eventual success
  - Test timeout after maximum retries
  - Validate error messages
```

**Performance Testing**:

```
Test 15: Deployment Time Impact
  - Measure baseline deployment time
  - Measure vault-enabled deployment time
  - Calculate performance delta
  - Target: less than thirty seconds added
  - Optimize if needed

Test 16: Concurrent Deployments
  - Deploy multiple instances simultaneously
  - Share same vault across deployments
  - Validate no rate limiting issues
  - Confirm all succeed
  - Test scalability

Test 17: Large Cluster Performance
  - Deploy ten node cluster
  - Measure time for all vault retrievals
  - Validate no bottlenecks
  - Confirm parallel retrieval works
  - Test cluster startup timing
```

### 7.2 Validation Criteria

**Deployment Success Criteria**:

```
Must have:
  - VM boots successfully
  - Managed Identity authenticated
  - Password retrieved from vault
  - Neo4j starts with retrieved password
  - Neo4j accessible via browser and Bolt
  - No errors in cloud-init logs
  - Deployment completes within expected time

Cluster additional criteria:
  - All nodes join cluster successfully
  - Cluster election completes
  - Database available across all nodes
  - High availability confirmed
```

**Security Success Criteria**:

```
Must have:
  - Zero passwords in deployment outputs
  - Zero passwords in deployment history
  - Zero passwords in VM metadata
  - Managed Identity permissions minimal (secrets user only)
  - Vault audit logs show access events
  - RBAC configured correctly
  - Network security validated
```

**Performance Success Criteria**:

```
Targets:
  - Vault retrieval adds less than thirty seconds to boot time
  - Retry logic does not cause excessive delays
  - Concurrent deployments scale linearly
  - No vault throttling encountered
  - Cluster formation time unchanged
```

## 8. Documentation Requirements

### 8.1 User Documentation

**Quick Start Guide**:
- Simple vault deployment walkthrough
- Copy-paste ready commands
- Common troubleshooting tips
- Expected output examples

**Comprehensive Deployment Guide**:
- All vault modes explained
- Parameter reference
- Architecture diagrams
- Best practices
- Security considerations

**Migration Guide**:
- Assessment of current deployment
- Step-by-step migration procedure
- Rollback instructions
- Validation checklist
- FAQ section

**Troubleshooting Guide**:
- Common error messages and solutions
- Diagnostic procedures
- Log locations and interpretation
- Support escalation path
- Known issues and workarounds

### 8.2 Operator Documentation

**Operations Runbook**:
- Daily operations procedures
- Password rotation process
- Vault maintenance tasks
- Monitoring and alerting setup
- Incident response procedures

**Security and Compliance Guide**:
- RBAC configuration
- Audit log analysis
- Compliance reporting
- Policy configuration
- Security best practices

**Disaster Recovery Guide**:
- Backup procedures
- Recovery procedures
- RTO and RPO objectives
- Test scenarios
- Contact information

### 8.3 Developer Documentation

**Architecture Decision Records**:
- Why Key Vault chosen over alternatives
- Why Managed Identity over service principals
- Why cloud-init over VM extensions
- Design trade-offs documented

**Implementation Guide**:
- Code structure explanation
- Template logic documentation
- Cloud-init script details
- Error handling patterns
- Testing approach

**Contribution Guide**:
- How to submit improvements
- Testing requirements
- Code review process
- Release procedures

## 9. Success Metrics

### 9.1 Phase 1 Success Metrics

```
Deployment Success Rate:
  - Target: 100% of test deployments succeed
  - Measurement: Automated test results
  - Threshold: Zero failures in regression tests

Documentation Completeness:
  - Target: All user scenarios documented
  - Measurement: Documentation review checklist
  - Threshold: All items checked off

Backward Compatibility:
  - Target: Zero breaking changes
  - Measurement: Existing deployments still work
  - Threshold: No regression in any scenario
```

### 9.2 Phase 2 Success Metrics

```
Secret Exposure Elimination:
  - Target: Zero passwords in deployment metadata
  - Measurement: Security scan of all outputs
  - Threshold: No secrets found in any location

Vault Retrieval Reliability:
  - Target: 99.9% successful retrievals
  - Measurement: Cloud-init log analysis
  - Threshold: Less than 0.1% failure rate

Performance Impact:
  - Target: Less than thirty seconds added to deployment
  - Measurement: Timing analysis
  - Threshold: Mean time increase under threshold
```

### 9.3 Phase 3 Success Metrics

```
Marketplace Adoption:
  - Target: 80% of new deployments use vault mode
  - Measurement: Telemetry data
  - Threshold: Majority adoption within three months

User Satisfaction:
  - Target: Positive feedback on vault experience
  - Measurement: Survey responses
  - Threshold: 90% satisfaction rating

Certification Success:
  - Target: Pass Marketplace security certification
  - Measurement: Certification report
  - Threshold: Zero critical findings
```

### 9.4 Phase 4 Success Metrics

```
Migration Completion:
  - Target: 100% of deployments migrated
  - Measurement: Deployment inventory
  - Threshold: Zero password-based deployments remain

Audit Coverage:
  - Target: 100% of secret access audited
  - Measurement: Audit log coverage analysis
  - Threshold: No gaps in audit trail

Code Simplification:
  - Target: Remove 50% of conditional logic
  - Measurement: Lines of code analysis
  - Threshold: Significant reduction in complexity
```

## 10. Risk Assessment and Mitigation

### 10.1 Technical Risks

**Risk: Managed Identity Propagation Delays**

Probability: High (known Azure platform behavior)
Impact: Medium (deployment delays, user frustration)

Mitigation:
- Implement robust retry logic with exponential backoff
- Set realistic timeout values (three minutes)
- Provide clear progress indicators in logs
- Document expected delay in user documentation
- Consider ARM template dependency ordering

Contingency:
- If propagation consistently exceeds three minutes, escalate to Azure support
- Consider alternative authentication methods if persistent
- Implement circuit breaker pattern for excessive delays

**Risk: Key Vault Service Outage**

Probability: Low (Azure SLA 99.9%)
Impact: High (deployments fail, operations blocked)

Mitigation:
- Design for eventual consistency with retries
- Implement graceful degradation where possible
- Monitor Azure service health proactively
- Document emergency procedures
- Consider multi-region vault replication for critical deployments

Contingency:
- Emergency override to use password parameter temporarily
- Documented escalation to Azure support
- Communication plan for affected users

**Risk: Breaking Changes in Azure APIs**

Probability: Low (APIs versioned and maintained)
Impact: Medium (code updates required)

Mitigation:
- Use stable API versions only
- Pin API versions in code explicitly
- Monitor Azure breaking change announcements
- Subscribe to Azure updates mailing list
- Test with preview API versions before GA

Contingency:
- Maintain support for multiple API versions during transition
- Implement feature flags for new API adoption
- Rollback capability to previous API version

### 10.2 Security Risks

**Risk: Vault Misconfiguration Exposes Secrets**

Probability: Medium (user configuration errors)
Impact: High (security breach)

Mitigation:
- Enforce RBAC by default (not access policies)
- Require soft delete and purge protection
- Validate configuration in deployment script
- Provide secure defaults in templates
- Regular security audits and scanning

Contingency:
- Automated detection of misconfigured vaults
- Alert and remediation workflow
- Incident response plan for exposure events
- Password rotation on suspected compromise

**Risk: Compromised Managed Identity**

Probability: Low (requires VM compromise)
Impact: Medium (password access only, not vault admin)

Mitigation:
- Least privilege: secrets user role only
- Scope to specific secret when possible
- Monitor for unusual access patterns
- Implement conditional access policies
- Regular security assessments

Contingency:
- Revoke compromised identity immediately
- Rotate affected passwords
- Review audit logs for unauthorized access
- Document incident and lessons learned

### 10.3 Operational Risks

**Risk: Vault Deletion Causes Outage**

Probability: Low (purge protection enabled)
Impact: High (passwords unavailable)

Mitigation:
- Enable purge protection on all vaults
- Enable soft delete with ninety day retention
- Tag vaults to prevent accidental deletion
- Azure Policy to prevent deletion
- Backup critical secrets to secondary vault

Contingency:
- Restore from soft delete within retention period
- Use backup vault for emergency access
- Document recovery procedure
- RCA and process improvement

**Risk: Migration Disrupts Production**

Probability: Medium (complex migration process)
Impact: High (production downtime)

Mitigation:
- Thorough testing in non-production first
- Phased migration approach
- Detailed rollback procedures
- Maintenance window scheduling
- Communication plan for stakeholders

Contingency:
- Immediate rollback on first sign of issue
- Keep previous configuration accessible
- Incident commander assigned
- Post-mortem analysis

### 10.4 Business Risks

**Risk: Marketplace Certification Delays**

Probability: Medium (certification process unpredictable)
Impact: Medium (delayed availability)

Mitigation:
- Engage Marketplace team early
- Address security requirements proactively
- Test certification criteria before submission
- Build in buffer time for iterations
- Maintain good relationship with certification team

Contingency:
- Continue with direct deployment support
- Phased rollout if partial approval
- Alternative distribution channels
- Regular status updates to stakeholders

**Risk: User Adoption Lower Than Expected**

Probability: Medium (change management challenge)
Impact: Medium (continued support burden)

Mitigation:
- Clear communication of benefits
- Simple migration path
- Excellent documentation
- Support during transition
- Showcase success stories

Contingency:
- Extend deprecation timeline if needed
- Additional training and support
- Incentivize adoption
- Gather feedback and iterate

## 11. Action Plan and Timeline

### 11.1 Immediate Actions (Weeks 1-2)

```
Action 1: Proposal Review and Approval
  - Present proposal to technical stakeholders
  - Gather feedback and concerns
  - Incorporate review comments
  - Obtain formal approval to proceed
  - Assign project team members

Action 2: Development Environment Setup
  - Create test Azure subscription or resource group
  - Set up test Key Vaults
  - Configure developer access and permissions
  - Prepare test data and scenarios
  - Set up CI/CD pipeline for testing

Action 3: Documentation Framework
  - Create documentation structure
  - Set up wiki or documentation repository
  - Define documentation standards
  - Assign documentation owners
  - Create initial templates
```

### 11.2 Phase 1 Timeline (Weeks 3-8)

```
Week 3-4: Bicep Template Development
  - Add vault parameters to template
  - Implement conditional logic for vault mode
  - Add Managed Identity RBAC assignment
  - Test template compilation
  - Peer review changes

Week 5-6: Cloud-Init Development
  - Implement vault retrieval logic
  - Add error handling and retries
  - Update password initialization
  - Test on standalone and cluster
  - Peer review changes

Week 7: Deployment Script Updates
  - Update deploy.sh with vault options
  - Implement vault creation logic
  - Add password generation
  - Test end-to-end deployment
  - Document script usage

Week 8: Testing and Documentation
  - Execute full test suite
  - Fix discovered issues
  - Complete user documentation
  - Conduct internal training
  - Prepare for Phase 2
```

### 11.3 Phase 2 Timeline (Weeks 9-14)

```
Week 9-10: Cloud-Init Hardening
  - Enhance error handling
  - Optimize retry logic
  - Add comprehensive logging
  - Test failure scenarios
  - Performance optimization

Week 11-12: Security Validation
  - Conduct security review
  - Penetration testing
  - Verify zero secret exposure
  - Audit trail validation
  - Address findings

Week 13: Migration Tooling
  - Develop migration scripts
  - Test migration procedures
  - Document migration paths
  - Create rollback procedures
  - Train operations team

Week 14: Pilot Deployment
  - Select pilot users
  - Execute pilot deployments
  - Gather feedback
  - Address issues
  - Refine documentation
```

### 11.4 Phase 3 Timeline (Weeks 15-22)

```
Week 15-17: Marketplace UI Development
  - Update createUiDefinition.json
  - Add vault configuration options
  - Implement auto-create vault flow
  - Test UI extensively
  - Peer review changes

Week 18-19: Marketplace Certification Prep
  - Review certification requirements
  - Address all checklist items
  - Conduct pre-certification testing
  - Prepare submission package
  - Submit for certification

Week 20-21: Certification Iteration
  - Address certification feedback
  - Retest and resubmit
  - Monitor certification progress
  - Prepare for publication
  - Update marketing materials

Week 22: Marketplace Launch
  - Publish updated Marketplace offer
  - Monitor initial deployments
  - Respond to user feedback
  - Document lessons learned
  - Celebrate success
```

### 11.5 Phase 4 Timeline (Months 7-12)

```
Month 7-9: Deprecation Warning Period
  - Announce deprecation timeline
  - Add warnings to documentation and UI
  - Implement telemetry for usage tracking
  - Support migration inquiries
  - Monitor adoption metrics

Month 10-11: Hard Deprecation
  - Update templates to fail without vault
  - Provide emergency override
  - Assist remaining migrations
  - Monitor for blockers
  - Communicate final deadline

Month 12: Cleanup and Optimization
  - Remove legacy code paths
  - Simplify template structure
  - Update all documentation
  - Archive old versions
  - Conduct retrospective
```

## 12. Appendices

### Appendix A: Azure Key Vault Pricing

```
Key Vault Standard SKU:
  - Operations: $0.03 per 10,000 transactions
  - Stored secrets: First 10,000 free, then $0.03 per 10,000 per month

Estimated monthly cost for typical Neo4j deployment:
  - One vault: minimal cost (within free tier)
  - One secret (password): $0.00
  - Retrieval operations: ~100 per month = $0.00
  - Total estimated: $0.00 - $0.10 per month

Cost comparison:
  - Current approach: $0.00 (no external services)
  - Key Vault approach: $0.00 - $0.10 per deployment per month
  - Security value: High (centralized management, audit, rotation)
  - Cost impact: Negligible
```

### Appendix B: Alternative Solutions Considered

```
Alternative 1: Azure Managed HSM
  - Higher security with dedicated HSM
  - Significantly higher cost (~$1,500 per month)
  - Overkill for password storage
  - Rejected due to cost and complexity

Alternative 2: Service Principal Credentials
  - Use service principal instead of Managed Identity
  - Requires storing client secret
  - Increases security risk (secret sprawl)
  - Rejected due to security concerns

Alternative 3: Custom Credential Service
  - Build custom API for password distribution
  - Adds infrastructure dependency
  - Increases maintenance burden
  - Rejected in favor of platform service

Alternative 4: HashiCorp Vault
  - Third-party secret management
  - Requires separate infrastructure
  - Adds licensing cost
  - Rejected for Azure-native solution
```

### Appendix C: Glossary

```
ARM: Azure Resource Manager
Bicep: Infrastructure as Code language for Azure
Cloud-Init: Industry-standard VM initialization tool
FQDN: Fully Qualified Domain Name
HSM: Hardware Security Module
IMDS: Instance Metadata Service
Managed Identity: Azure AD identity for Azure resources
RBAC: Role-Based Access Control
RG: Resource Group
SAS: Shared Access Signature
TLS: Transport Layer Security
VMSS: Virtual Machine Scale Set
```

### Appendix D: References

```
Azure Key Vault Documentation:
  - https://docs.microsoft.com/azure/key-vault/

Azure Managed Identity Documentation:
  - https://docs.microsoft.com/azure/active-directory/managed-identities-azure-resources/

Azure Marketplace Publishing Guide:
  - https://docs.microsoft.com/azure/marketplace/

Bicep Template Best Practices:
  - https://docs.microsoft.com/azure/azure-resource-manager/bicep/

Cloud-Init Documentation:
  - https://cloudinit.readthedocs.io/

Neo4j Security Best Practices:
  - https://neo4j.com/docs/operations-manual/current/security/
```

---

## Document Status and Approval

**Status**: Awaiting Review
**Version**: 1.0
**Last Updated**: 2025-11-18
**Next Review**: Upon stakeholder feedback

**Approvers**:
- Technical Lead: _Pending_
- Security Team: _Pending_
- Product Management: _Pending_
- Marketplace Team: _Pending_

**Change History**:
- 2025-11-18: Initial proposal created
