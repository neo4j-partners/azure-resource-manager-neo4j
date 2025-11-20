# Azure Key Vault Integration - Remaining Work (VAULT_V3)

**Date:** 2025-11-19
**Status:** Implementation Roadmap for Remaining Tasks

---

## Executive Summary

The core Key Vault integration is **94% complete**. All backend infrastructure, password generation, secure retrieval, and local deployment tooling is fully implemented and working. The primary remaining work focuses on **marketplace user experience** and **operational documentation**.

**Current State:**
- Local/enterprise deployments can use Key Vault automatically
- Passwords are generated securely and stored in Key Vault
- VMs retrieve passwords at runtime using managed identity
- No passwords written to disk or logs
- Cross-resource-group vault support working

**What's Missing:**
- Marketplace UI to select Key Vault mode
- Documentation for marketplace users
- Password rotation procedures
- Team adoption guides

---

## Priority 1: Marketplace User Interface (Phase 7)

**File:** `marketplace/neo4j-enterprise/createUiDefinition.json`

**Current Problem:**
Marketplace users can only enter passwords directly in the Azure Portal UI. There is no option to specify an existing Key Vault, which means passwords are visible during deployment and stored in deployment metadata.

**What Needs to Be Done:**

### Add Password Mode Selector
Create a dropdown or radio button that lets users choose between:
- "Direct Password Entry" (current behavior, backward compatible)
- "Use Existing Key Vault" (new secure option)

### Add Key Vault Configuration Fields
When user selects "Use Existing Key Vault" mode, show additional fields:
- Key Vault name input box
- Secret name input box (with default value: neo4j-admin-password)
- Optional: Resource group selector for the vault

### Add Conditional Visibility Logic
The vault configuration fields should only appear when "Use Existing Key Vault" is selected. When "Direct Password Entry" is selected, show the current password input box.

### Add Information Messages
Include helpful text explaining:
- Why Key Vault is more secure
- Instructions that the vault must exist before deployment
- Instructions that the password must already be stored in the vault
- Link to documentation for pre-deployment setup

### Update Parameter Mapping
Ensure the createUiDefinition outputs map correctly to the Bicep template parameters:
- keyVaultName
- keyVaultResourceGroup
- adminPasswordSecretName
- adminPassword (only when direct mode selected)

### Testing Requirements
- Test marketplace deployment with direct password mode (ensure backward compatibility)
- Test marketplace deployment with vault mode
- Verify validation messages appear correctly
- Test with vault in same resource group
- Test with vault in different resource group

---

## Priority 2: Marketplace User Documentation (Phase 7)

**What Needs to Be Done:**

### Create Pre-Deployment Guide
Write a step-by-step guide titled "Using Key Vault with Neo4j Azure Marketplace Deployment" that explains:
- Why to use Key Vault instead of direct password entry
- How to create a Key Vault in Azure Portal before deployment
- How to generate a secure password (provide Azure CLI command)
- How to store the password as a secret in the vault
- How to grant the deploying user access to the vault
- How to select the vault during marketplace deployment

### Provide Example Azure CLI Commands
Include copy-paste ready commands for users who prefer CLI over Portal:
- Create Key Vault command
- Generate password command
- Store secret command
- Grant access command

### Add Troubleshooting Section
Document common issues and solutions:
- "Cannot access vault" - check access policies
- "Secret not found" - verify secret name matches
- "Deployment fails with vault error" - check vault exists in subscription

### Update Marketplace Listing Description
Add a bullet point to the marketplace offer description mentioning Key Vault support for secure password management.

### Create README in marketplace directory
Add or update README explaining the vault option for marketplace publishers reviewing the template.

---

## Priority 3: Standardized Naming and Team Adoption (Phase 5)

**What Needs to Be Done:**

### Document Naming Conventions
Create a standard for vault and secret naming:
- Vault naming pattern (example: kv-{environment}-neo4j or kv-neo4j-{region})
- Secret naming pattern (example: neo4j-admin-password)
- Resource group naming for vaults
- Tag standards for vault resources

### Create Deployment Checklist
Provide a pre-deployment checklist that teams can follow:
- Verify vault exists in correct subscription
- Verify vault exists in correct region
- Verify secret exists with correct name
- Verify deploying identity has vault access
- Verify managed identity will be granted access
- Verify vault has soft delete enabled
- Verify vault has purge protection enabled
- Record deployment date and vault details

### Create Team Training Materials
Develop onboarding documentation for teams explaining:
- When to use Key Vault vs direct password
- How the vault integration works (high-level architecture)
- How to create vaults for different environments (dev, staging, prod)
- How to manage access to vaults
- How to audit vault access

### Document Access Control Best Practices
Explain Azure RBAC roles for Key Vault:
- Who should have "Key Vault Secrets User" role
- Who should have "Key Vault Administrator" role
- How to use access policies vs RBAC
- How to audit access to secrets

### Create Runbook for Common Tasks
Document procedures for:
- Setting up a new deployment with vault
- Migrating existing deployment to vault
- Sharing vault access with team members
- Revoking vault access
- Reviewing vault audit logs

---

## Priority 4: Password Rotation Support (Phase 6)

**What Needs to Be Done:**

### Enhance Password Generation Script
Add rotation capability to `scripts/generate-password.sh`:
- Accept a flag like --rotate or --update-existing
- When rotation flag is present, generate new password and create new secret version
- Log rotation event with timestamp
- Ensure old versions are retained per retention policy

### Document Rotation Procedure
Create step-by-step rotation guide:
- When to rotate passwords (compliance schedule, security incident, etc.)
- How to generate new password version
- How to plan maintenance window for Neo4j restart
- How to update Neo4j with new password
- How to verify cluster health after rotation
- How to rollback if rotation fails

### Add Rotation Automation Options
Document or create tools for:
- Automated rotation on schedule (Azure Automation, GitHub Actions)
- Notification when rotation is due
- Verification that rotation completed successfully

### Define Secret Version Retention Policy
Establish policy for old secret versions:
- How many old versions to keep
- How long to retain old versions
- When to purge old versions
- How to audit version history

### Create Neo4j Password Update Procedure
Document how to update Neo4j after password rotation:
- For standalone deployments
- For cluster deployments (all nodes)
- For read replica deployments
- Command to change Neo4j password
- How to verify password change was successful
- How to handle connection failures during rotation

---

## Priority 5: Future Enhancements (Phase 8)

**What Needs to Be Done:**

### Auto-Create Vault Option for Marketplace
Allow marketplace users to have vault created automatically during deployment:
- Add new option "Create New Key Vault" in marketplace UI
- Accept vault name parameter from user
- Bicep template creates vault as part of deployment
- Bicep template generates password (or call deployment script)
- Store password in newly created vault
- Grant managed identity access to vault

### Design Considerations for Auto-Create
Address these questions:
- Should vault be in same resource group as deployment or separate?
- Should vault be deleted when deployment is deleted or persist?
- How to handle vault name conflicts if vault already exists
- How to communicate vault details to user after deployment
- Security implications of auto-generated passwords

### Implementation Approach
Create optional Bicep module for vault creation:
- Module only invoked if user selects "Create New Key Vault"
- Module creates vault with appropriate settings (soft delete, purge protection)
- Module generates or accepts pre-generated password
- Module stores password as secret
- Module grants access to managed identity
- Module outputs vault details for user reference

### Documentation for Auto-Create Mode
Explain to users:
- When to use auto-create vs existing vault
- Pros and cons of auto-create
- What happens to vault if deployment is deleted
- How to access vault after deployment
- How to manage vault access going forward

---

## Additional Considerations

### Testing and Validation

**End-to-End Testing:**
- Test full marketplace deployment with vault mode
- Test deployment in multiple Azure regions
- Test with vaults in different subscriptions
- Test with different vault access control models (RBAC vs access policies)
- Test password retrieval on all VM types (standalone, cluster, read replica)
- Test deployment failure scenarios (vault not found, access denied, secret not found)

**Validation Automation:**
- Extend deployment validation script to test vault integration
- Verify managed identity has vault access after deployment
- Verify VMs can retrieve password from vault
- Verify no password appears in deployment logs or metadata

### Security Hardening

**Additional Security Measures:**
- Document firewall rules for vault (allow only from Azure services)
- Document private endpoint setup for vault
- Explain how to enable vault diagnostic logging
- Explain how to monitor vault access with Azure Monitor
- Document compliance requirements (SOC 2, HIPAA, PCI-DSS)

**Audit and Compliance:**
- How to review vault audit logs
- How to set up alerts for unauthorized access
- How to generate compliance reports
- How to demonstrate password never written to disk

### Migration Path for Existing Deployments

**Migration Procedure:**
- Create vault and store current password
- Update deployment configuration to reference vault
- Redeploy or update existing deployment
- Verify VMs can retrieve from vault
- Remove direct password from configuration
- Validate no passwords in deployment metadata

**Rollback Plan:**
- How to revert to direct password if vault integration fails
- How to maintain availability during migration
- Testing migration in non-production environment first

---

## Success Criteria

The Key Vault integration will be considered complete when:

1. Marketplace users can select Key Vault mode in the Azure Portal UI
2. Marketplace deployment succeeds using existing Key Vault
3. No passwords visible in marketplace UI or deployment metadata
4. Documentation exists for marketplace users explaining setup
5. Naming conventions documented and adopted by team
6. Password rotation procedure documented and tested
7. Team training materials available
8. All security best practices documented
9. End-to-end testing completed for all scenarios
10. Compliance and audit requirements satisfied

---

## Timeline Recommendation

### Week 1-2: Critical Path (Marketplace UI)
- Update createUiDefinition.json with vault mode selector
- Test marketplace deployment with vault mode
- Create marketplace user documentation

### Week 3: Documentation and Adoption
- Write pre-deployment guide for marketplace users
- Document naming conventions
- Create deployment checklist
- Write team training materials

### Week 4: Password Rotation
- Enhance generate-password.sh with rotation support
- Document rotation procedure
- Test rotation in non-production environment

### Future: Optional Enhancements
- Implement auto-create vault option
- Automate rotation scheduling
- Add advanced monitoring and alerting

---

## Summary

The Key Vault integration is nearly complete with robust backend implementation. The primary gaps are user-facing:

**Most Critical:**
- Marketplace UI to enable vault mode selection
- Documentation for marketplace users

**Important:**
- Team adoption documentation
- Password rotation procedures

**Nice to Have:**
- Auto-create vault option
- Rotation automation

Completing the marketplace UI (Phase 7) should be the immediate focus, as it's the only blocker preventing marketplace users from benefiting from the secure Key Vault integration that's already built and working in the backend.
