# ARM Template Deployment Troubleshooting

## Issue Summary

The deployment monitoring was showing "Unknown" status because deployments were failing validation but the Azure CLI bug was hiding the actual error message.

## Root Cause

1. **Authorization Error**: Your Azure account lacks permissions to create custom role definitions and role assignments required by the ARM template
2. **Azure CLI Bug**: Azure CLI 2.77.0 shows "The content for this response was already consumed" instead of the actual validation error
3. **Script Issue**: The deployment script treated this as a spurious error and reported success when deployment actually failed

## Fix Applied

Updated `localtests/src/orchestrator.py` with:

### 1. Pre-Deployment Validation
- Added `validate_deployment()` method that runs `az deployment group validate --debug`
- Parses debug output to extract actual error messages
- Validation runs before attempting deployment

### 2. Improved Error Detection
- Added `_extract_validation_error()` to parse authorization errors from debug output
- Detects specific error patterns:
  - Authorization failures
  - Invalid template errors
  - HTTP status codes

### 3. Deployment Verification
- When Azure CLI shows spurious error after validation passes:
  - Waits 3 seconds for Azure to register deployment
  - Verifies deployment was actually created using `az deployment group show`
  - Reports accurate success/failure status

## Required Azure Permissions

To deploy this ARM template, you need **one of these roles**:

- **Owner** (at subscription or resource group level)
- **User Access Administrator** + **Contributor**

The template creates these resources requiring elevated permissions:
- Custom role definitions (`Microsoft.Authorization/roleDefinitions/write`)
- Role assignments (`Microsoft.Authorization/roleAssignments/write`)

### Check Your Current Permissions

```bash
# View your current role assignments
az role assignment list --assignee your.email@domain.com --output table

# Check for required roles
az role assignment list \
  --assignee your.email@domain.com \
  --query "[?roleDefinitionName=='Owner' || roleDefinitionName=='User Access Administrator']" \
  --output table
```

## Resolution Options

### Option 1: Request Permissions (Recommended)
Contact your Azure administrator to grant you one of the required roles:

```bash
# Example: Grant Owner role at resource group level
az role assignment create \
  --assignee your.email@domain.com \
  --role Owner \
  --resource-group <resource-group-name>

# Or at subscription level
az role assignment create \
  --assignee your.email@domain.com \
  --role Owner \
  --subscription <subscription-id>
```

### Option 2: Use Existing Roles
If you cannot get elevated permissions, the ARM template needs to be modified to:
- Remove custom role definition creation
- Use built-in Azure roles instead
- Requires template architecture changes

### Option 3: Deploy via Service Principal
Create a service principal with required permissions:

```bash
# Create service principal
az ad sp create-for-rbac --name "neo4j-deployer" --role Owner --scopes /subscriptions/<subscription-id>

# Use service principal for deployment
az login --service-principal \
  -u <app-id> \
  -p <password> \
  --tenant <tenant-id>
```

## Verification Commands

### Before Deployment
```bash
# Validate template and see actual errors
az deployment group validate \
  --resource-group <rg-name> \
  --template-file marketplace/neo4j-enterprise/mainTemplate.json \
  --parameters <params-file> \
  --debug 2>&1 | grep -E "(Response status:|Authorization|InvalidTemplate)"
```

### During Deployment
```bash
# Check if deployment exists
az deployment group list \
  --resource-group <rg-name> \
  --output table

# Monitor specific deployment
az deployment group show \
  --resource-group <rg-name> \
  --name <deployment-name> \
  --query "{name:name, state:properties.provisioningState}" \
  --output table
```

### After Deployment
```bash
# View deployment operations for errors
az deployment operation group list \
  --resource-group <rg-name> \
  --name <deployment-name> \
  --query "[?properties.provisioningState=='Failed']" \
  --output table
```

## Testing the Fix

The updated script now:

1. **Validates before deploying** - catches authorization errors early
2. **Shows clear error messages** - no more cryptic Azure CLI bugs
3. **Verifies deployment creation** - confirms deployment actually exists

### Example Output (With Fix)

```
Submitting deployment: neo4j-deploy-standalone-v5-20251116-140140
Validating template...
✗ Template validation failed: neo4j-deploy-standalone-v5-20251116-140140
Authorization Error: Your Azure account lacks permission to perform 'Microsoft.Authorization/roleDefinitions/write'.
This template requires Owner or User Access Administrator role on the subscription.
Contact your Azure administrator to grant the necessary permissions.
```

### Run New Deployment

Once you have the required permissions:

```bash
cd localtests
uv run test-arm.py deploy --scenario standalone-v5
```

The script will now:
- Validate the template first
- Show clear authorization errors if permissions are missing
- Verify deployment was created before reporting success
- Accurately monitor deployment status

## Related Issues

- Azure CLI Issue: https://github.com/Azure/azure-cli/issues/31581
- Fixed in Azure CLI (but regression in 2.77.0)
- Workaround: Use `--debug` flag to see actual errors
