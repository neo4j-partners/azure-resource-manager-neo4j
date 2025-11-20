# Using Azure Key Vault with Neo4j Marketplace Deployment

**Recommended for Production Deployments**

This guide explains how to use Azure Key Vault for secure password management when deploying Neo4j from the Azure Marketplace.

---

## Why Use Azure Key Vault?

Azure Key Vault provides enterprise-grade security benefits:

- **No Password Exposure** - Passwords never appear in the Azure Portal UI or deployment logs
- **Centralized Management** - Store and manage secrets in one secure location
- **Access Control** - Fine-grained permissions using Azure RBAC and access policies
- **Audit Logging** - Track all secret access with Azure Monitor
- **Compliance** - Meets SOC 2, HIPAA, PCI-DSS, and other security standards
- **Rotation Support** - Update passwords without redeploying infrastructure

---

## Prerequisites

Before deploying Neo4j from the marketplace with Key Vault, you need:

1. An Azure subscription with permissions to create Key Vaults
2. Azure CLI installed (or use Azure Cloud Shell)
3. Permissions to create secrets in the vault
4. Permissions to grant access policies on the vault

---

## Step-by-Step Setup Guide

### Step 1: Create an Azure Key Vault

You can create a Key Vault using the Azure Portal or Azure CLI.

#### Option A: Using Azure Portal

1. Navigate to **Create a resource** > **Security** > **Key Vault**
2. Fill in the required fields:
   - **Subscription**: Choose your subscription
   - **Resource Group**: Create new or use existing (can be different from Neo4j deployment)
   - **Key Vault Name**: Enter a unique name (3-24 characters, alphanumeric and hyphens)
   - **Region**: Choose the same region where you'll deploy Neo4j
   - **Pricing Tier**: Standard (sufficient for most deployments)
3. Click **Review + Create**, then **Create**

#### Option B: Using Azure CLI

```bash
# Set your variables
VAULT_NAME="kv-neo4j-prod"  # Change this to your preferred name
RESOURCE_GROUP="neo4j-keyvault-rg"  # Resource group for the vault
LOCATION="eastus"  # Change to your preferred region

# Create resource group (if it doesn't exist)
az group create \
  --name $RESOURCE_GROUP \
  --location $LOCATION

# Create Key Vault
az keyvault create \
  --name $VAULT_NAME \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --enable-soft-delete true \
  --enable-purge-protection true
```

**Important Notes:**
- Key Vault names must be globally unique across Azure
- Enable soft-delete and purge-protection for production environments
- The vault can be in a different resource group than your Neo4j deployment

---

### Step 2: Generate a Secure Password

Generate a strong password for Neo4j admin account:

#### Option A: Using OpenSSL (Recommended)

```bash
# Generate a 32-character password with high entropy
openssl rand -base64 32 | tr -d '/+=' | head -c 32
```

#### Option B: Using PowerShell

```powershell
# Generate a 32-character password
-join ((33..126) | Get-Random -Count 32 | ForEach-Object {[char]$_})
```

#### Option C: Using Azure Cloud Shell

```bash
# Azure Cloud Shell has openssl available
openssl rand -base64 32 | tr -d '/+=' | head -c 32
```

**Password Requirements:**
- 12-72 characters long
- Must contain characters from at least 3 of: uppercase, lowercase, numbers, special characters
- Avoid characters that require complex escaping: `$`, `` ` ``, `\`

**Important:** Copy the generated password - you'll need it in the next step.

---

### Step 3: Store the Password in Key Vault

Store the generated password as a secret in your Key Vault:

```bash
# Set your variables
VAULT_NAME="kv-neo4j-prod"  # Your vault name from Step 1
SECRET_NAME="neo4j-admin-password"  # Default name (can be changed)
PASSWORD="YourGeneratedPasswordHere"  # Paste the password from Step 2

# Store the secret
az keyvault secret set \
  --vault-name $VAULT_NAME \
  --name $SECRET_NAME \
  --value "$PASSWORD"
```

**Verify the secret was stored:**

```bash
# List secrets in the vault (shows names only, not values)
az keyvault secret list \
  --vault-name $VAULT_NAME \
  --output table

# Retrieve the secret to verify (optional)
az keyvault secret show \
  --vault-name $VAULT_NAME \
  --name $SECRET_NAME \
  --query "value" \
  --output tsv
```

**Important Notes:**
- The default secret name is `neo4j-admin-password` - use this unless you have a specific naming convention
- Keep the password stored somewhere safe (password manager) for initial Neo4j login
- The password will be used for both the VM admin account and Neo4j database

---

### Step 4: Grant Your Account Access to the Vault

Ensure you have permissions to read secrets from the vault:

```bash
# Get your current user/service principal Object ID
USER_OBJECT_ID=$(az ad signed-in-user show --query id --output tsv)

# Grant yourself "Key Vault Secrets User" role
az role assignment create \
  --role "Key Vault Secrets User" \
  --assignee $USER_OBJECT_ID \
  --scope "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$VAULT_NAME"
```

**Alternative: Using Access Policies (Legacy)**

```bash
# Grant get and list permissions via access policy
az keyvault set-policy \
  --name $VAULT_NAME \
  --upn $(az account show --query user.name --output tsv) \
  --secret-permissions get list
```

---

### Step 5: Deploy Neo4j from Azure Marketplace

Now you're ready to deploy Neo4j using the Key Vault:

1. Navigate to the **Neo4j Enterprise** listing in the Azure Marketplace
2. Click **Create**
3. On the **Neo4j Config** tab, you'll see the **Password Management** section
4. Select **Use Azure Key Vault (Recommended)**
5. Fill in the Key Vault details:
   - **Key Vault Name**: Enter your vault name (e.g., `kv-neo4j-prod`)
   - **Key Vault Resource Group**: Enter the resource group containing the vault
   - **Admin Password Secret Name**: Enter the secret name (default: `neo4j-admin-password`)
6. Complete the rest of the deployment configuration (VM size, node count, etc.)
7. Click **Review + Create**, then **Create**

---

### Step 6: Deployment Process

During deployment, the following happens automatically:

1. **ARM/Bicep Deployment** - The template reads your Key Vault parameters
2. **Managed Identity Created** - A user-assigned managed identity is created for the VMs
3. **Access Policy Granted** - The managed identity is automatically granted access to your Key Vault
4. **VMs Provisioned** - Virtual machines are created with the managed identity assigned
5. **Password Retrieval** - At boot, VMs retrieve the password from Key Vault using the managed identity
6. **Neo4j Configuration** - The password is used to set the Neo4j admin password (never written to disk)

**No manual intervention required** - the entire process is automated and secure.

---

## Accessing Your Neo4j Deployment

After deployment completes:

1. Navigate to your deployment outputs in the Azure Portal
2. Copy the **Neo4jBrowserURL** or **Neo4jClusterBrowserURL**
3. Open the URL in your browser
4. Log in with:
   - **Username**: `neo4j`
   - **Password**: The password you stored in Key Vault (from Step 2)

---

## Troubleshooting

### Issue: "Cannot access Key Vault during deployment"

**Cause:** Your account doesn't have permissions to read secrets from the vault.

**Solution:**
```bash
# Grant yourself access
az keyvault set-policy \
  --name $VAULT_NAME \
  --upn $(az account show --query user.name --output tsv) \
  --secret-permissions get list
```

---

### Issue: "Secret not found"

**Cause:** The secret name doesn't match what you entered in the deployment UI.

**Solution:**
```bash
# List all secrets to verify the name
az keyvault secret list \
  --vault-name $VAULT_NAME \
  --output table

# Check if the secret exists
az keyvault secret show \
  --vault-name $VAULT_NAME \
  --name neo4j-admin-password
```

---

### Issue: "Deployment fails with Key Vault access error"

**Cause:** The managed identity can't access the vault (cross-subscription or permissions issue).

**Solution:**
1. Ensure the Key Vault and Neo4j deployment are in the **same subscription**
2. Verify the vault resource group name is correct
3. Check the deployment error message for specific details
4. Ensure the vault allows access from Azure services

---

### Issue: "Neo4j won't start after deployment"

**Cause:** Password retrieval from vault failed, or password doesn't meet Neo4j requirements.

**Solution:**
1. SSH into the VM (if accessible)
2. Check cloud-init logs: `sudo cat /var/log/cloud-init-output.log`
3. Look for errors related to "Key Vault" or "password"
4. Verify the password in the vault meets complexity requirements

---

### Issue: "Key Vault in different subscription"

**Current Limitation:** The Key Vault must be in the same Azure subscription as the Neo4j deployment.

**Workaround:**
- Create a new Key Vault in the deployment subscription
- Copy the password secret to the new vault
- Use the new vault for deployment

---

## Security Best Practices

### 1. Use Separate Resource Groups

Keep your Key Vault in a separate resource group from Neo4j deployments:
- **Vault Resource Group**: `neo4j-keyvault-rg` (persistent)
- **Deployment Resource Group**: `neo4j-prod-rg` (can be deleted/recreated)

This prevents accidental deletion of the vault when cleaning up deployments.

---

### 2. Enable Vault Protection

Always enable these Key Vault features for production:

```bash
az keyvault update \
  --name $VAULT_NAME \
  --enable-soft-delete true \
  --enable-purge-protection true
```

- **Soft Delete**: Allows recovery of deleted secrets for 90 days
- **Purge Protection**: Prevents permanent deletion during soft-delete period

---

### 3. Use RBAC Instead of Access Policies

For new deployments, use Azure RBAC (more modern and flexible):

```bash
# Assign "Key Vault Secrets User" role to users who need read access
az role assignment create \
  --role "Key Vault Secrets User" \
  --assignee user@example.com \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$VAULT_NAME"
```

---

### 4. Enable Audit Logging

Monitor all access to your vault:

```bash
# Enable diagnostics (requires a Log Analytics workspace)
az monitor diagnostic-settings create \
  --name "KeyVaultAuditLogs" \
  --resource "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$VAULT_NAME" \
  --logs '[{"category": "AuditEvent", "enabled": true}]' \
  --workspace "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$LOG_RG/providers/Microsoft.OperationalInsights/workspaces/$WORKSPACE_NAME"
```

---

### 5. Implement Secret Rotation

Rotate passwords regularly for compliance:

```bash
# Generate new password
NEW_PASSWORD=$(openssl rand -base64 32 | tr -d '/+=' | head -c 32)

# Update the secret (creates new version)
az keyvault secret set \
  --vault-name $VAULT_NAME \
  --name $SECRET_NAME \
  --value "$NEW_PASSWORD"

# Update Neo4j password (requires Neo4j restart or live update)
# See Password Rotation Guide for details
```

---

### 6. Restrict Network Access (Optional)

For highly sensitive deployments, restrict vault access:

```bash
# Allow access only from specific virtual networks
az keyvault network-rule add \
  --name $VAULT_NAME \
  --vnet-name $VNET_NAME \
  --subnet $SUBNET_NAME

# Deny public access
az keyvault update \
  --name $VAULT_NAME \
  --default-action Deny
```

**Warning:** This requires careful planning for deployment access.

---

## Password Rotation Procedure

To rotate the Neo4j password after deployment:

### 1. Generate and Store New Password

```bash
# Generate new password
NEW_PASSWORD=$(openssl rand -base64 32 | tr -d '/+=' | head -c 32)

# Update secret in vault (creates new version)
az keyvault secret set \
  --vault-name $VAULT_NAME \
  --name $SECRET_NAME \
  --value "$NEW_PASSWORD"
```

### 2. Update Neo4j Password

**Option A: Using Cypher (Live Update)**

```bash
# Connect to Neo4j and run this Cypher command
ALTER CURRENT USER SET PASSWORD FROM '$OLD_PASSWORD' TO '$NEW_PASSWORD';
```

**Option B: Using neo4j-admin (Requires Restart)**

```bash
# SSH into each Neo4j VM and run:
sudo neo4j-admin dbms set-initial-password "$NEW_PASSWORD"
sudo systemctl restart neo4j
```

### 3. Verify Access

Test the new password by logging into Neo4j Browser with the new credentials.

---

## Comparison: Key Vault vs Direct Password

| Feature | Key Vault Mode | Direct Password Mode |
|---------|----------------|---------------------|
| **Password Visibility** | Never visible in UI | Visible in Azure Portal |
| **Deployment Metadata** | Only vault name stored | Password stored (encrypted) |
| **Audit Logging** | Full audit trail in vault | Limited to deployment logs |
| **Rotation** | Update vault secret | Requires redeployment |
| **Compliance** | Meets SOC 2, HIPAA, PCI | May not meet requirements |
| **Setup Complexity** | Requires pre-deployment setup | Simple, immediate |
| **Best For** | Production environments | Development/testing |

---

## Additional Resources

- [Azure Key Vault Documentation](https://docs.microsoft.com/azure/key-vault/)
- [Azure Key Vault Best Practices](https://docs.microsoft.com/azure/key-vault/general/best-practices)
- [Neo4j Security Documentation](https://neo4j.com/docs/operations-manual/current/security/)
- [Azure Managed Identity Documentation](https://docs.microsoft.com/azure/active-directory/managed-identities-azure-resources/)

---

## Support

For issues related to:
- **Key Vault setup**: Contact Azure Support or consult Azure documentation
- **Neo4j deployment**: Contact Neo4j Support or open an issue on the GitHub repository
- **Integration issues**: Check the Troubleshooting section above

---

**Last Updated:** 2025-11-19

**Document Version:** 1.0
