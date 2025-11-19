# Azure Entra ID Setup for GitHub Actions

This document provides step-by-step instructions for configuring Azure authentication for the GitHub Actions workflows in this repository.

## Overview

The GitHub Actions workflows (`.github/workflows/enterprise.yml` and `.github/workflows/community.yml`) require Azure credentials to:
- Create and delete resource groups
- Deploy ARM/Bicep templates
- Run Azure CLI commands for testing

Authentication is handled via a **Service Principal** (App Registration) in Azure Entra ID (formerly Azure Active Directory).

## Prerequisites

- Azure subscription with appropriate permissions to create service principals
- Azure CLI installed locally (`az` command)
- Owner or User Access Administrator role on the Azure subscription (required to assign roles)
- Admin access to the GitHub repository to add secrets

## Step 1: Create a Service Principal

### Option A: Using Automated Scripts (Recommended)

#### Python Script (Recommended)

Use the Python-based setup tool for the best experience with rich formatting and error handling:

```bash
# Login to Azure first
az login

# Run the Python setup script
cd deployments
uv run setup-azure-credentials

# With custom options
uv run setup-azure-credentials --name "my-sp-name" --subscription "xxx-xxx"

# Show help
uv run setup-azure-credentials --help
```

**Features:**
- Rich colored terminal output
- Interactive prompts and confirmations
- Automatic error detection and fallback strategies
- Handles permission issues gracefully
- Validates JSON output

#### Bash Script (Alternative)

For environments without Python/uv, use the bash script:

```bash
# Login to Azure first
az login

# Run the setup script
./scripts/setup-azure-credentials.sh
```

The script will:
- Verify prerequisites (Azure CLI, login status)
- Confirm your Azure subscription
- Check for existing service principals with the same name
- Create the service principal with Contributor role
- Save credentials to `azure-credentials.json` (with secure permissions)
- Add the filename to `.gitignore`
- Display next steps for adding to GitHub

**Script Options:**
```bash
# Use custom service principal name
./scripts/setup-azure-credentials.sh --name "my-custom-sp-name"

# Use specific subscription
./scripts/setup-azure-credentials.sh --subscription "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

# Save to custom output file
./scripts/setup-azure-credentials.sh --output "my-credentials.json"

# Show help
./scripts/setup-azure-credentials.sh --help
```

#### Manual Setup (Alternative)

If you prefer to run the commands manually:

1. **Login to Azure CLI:**
   ```bash
   az login
   ```

2. **Set your subscription** (if you have multiple):
   ```bash
   az account set --subscription "<subscription-id-or-name>"
   ```

3. **Create the service principal:**
   ```bash
   az ad sp create-for-rbac \
     --name "github-actions-neo4j-deploy" \
     --role "Contributor" \
     --scopes "/subscriptions/<subscription-id>" \
     --sdk-auth
   ```

   **Important:**
   - Replace `<subscription-id>` with your actual Azure subscription ID
   - The `--sdk-auth` flag outputs credentials in the JSON format required by GitHub Actions
   - The name `github-actions-neo4j-deploy` can be customized

4. **Save the output** - it will look like this:
   ```json
   {
     "clientId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
     "clientSecret": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
     "subscriptionId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
     "tenantId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
     "activeDirectoryEndpointUrl": "https://login.microsoftonline.com",
     "resourceManagerEndpointUrl": "https://management.azure.com/",
     "activeDirectoryGraphResourceId": "https://graph.windows.net/",
     "sqlManagementEndpointUrl": "https://management.core.windows.net:8443/",
     "galleryEndpointUrl": "https://gallery.azure.com/",
     "managementEndpointUrl": "https://management.core.windows.net/"
   }
   ```

   **⚠️ SECURITY WARNING:** This output contains sensitive credentials. Store it securely and never commit it to source control.

### Option B: Using Azure Portal

1. **Navigate to Entra ID:**
   - Go to the [Azure Portal](https://portal.azure.com)
   - Search for and select **Microsoft Entra ID** (or **Azure Active Directory**)

2. **Create App Registration:**
   - In the left menu, select **App registrations**
   - Click **+ New registration**
   - Set the following:
     - **Name:** `github-actions-neo4j-deploy`
     - **Supported account types:** Accounts in this organizational directory only
     - **Redirect URI:** Leave blank
   - Click **Register**

3. **Note the Application Details:**
   - On the **Overview** page, copy:
     - **Application (client) ID** → This is your `clientId`
     - **Directory (tenant) ID** → This is your `tenantId`

4. **Create a Client Secret:**
   - In the left menu, select **Certificates & secrets**
   - Click **+ New client secret**
   - Set:
     - **Description:** `GitHub Actions Secret`
     - **Expires:** Choose appropriate duration (recommended: 12-24 months)
   - Click **Add**
   - **⚠️ IMMEDIATELY COPY** the **Value** field → This is your `clientSecret`
   - **Note:** You cannot retrieve this value again after leaving the page

5. **Assign Azure RBAC Role:**
   - Navigate to **Subscriptions** in the Azure Portal
   - Select your subscription
   - Click **Access control (IAM)** in the left menu
   - Click **+ Add** → **Add role assignment**
   - Configure:
     - **Role:** Contributor
     - **Assign access to:** User, group, or service principal
     - **Members:** Search for `github-actions-neo4j-deploy` and select it
   - Click **Review + assign**

## Step 2: Construct the Credentials JSON

Using the values obtained above, create a JSON object with this exact structure:

```json
{
  "clientId": "<Application-Client-ID>",
  "clientSecret": "<Client-Secret-Value>",
  "subscriptionId": "<Azure-Subscription-ID>",
  "tenantId": "<Directory-Tenant-ID>",
  "activeDirectoryEndpointUrl": "https://login.microsoftonline.com",
  "resourceManagerEndpointUrl": "https://management.azure.com/",
  "activeDirectoryGraphResourceId": "https://graph.windows.net/",
  "sqlManagementEndpointUrl": "https://management.core.windows.net:8443/",
  "galleryEndpointUrl": "https://gallery.azure.com/",
  "managementEndpointUrl": "https://management.core.windows.net/"
}
```

**Replace the placeholders:**
- `<Application-Client-ID>` → Application (client) ID from step 1
- `<Client-Secret-Value>` → Client secret value from step 1
- `<Azure-Subscription-ID>` → Your Azure subscription ID
- `<Directory-Tenant-ID>` → Directory (tenant) ID from step 1

**To get your subscription ID:**
```bash
az account show --query id --output tsv
```

## Step 3: Add Secret to GitHub Repository

1. **Navigate to GitHub Repository Settings:**
   - Go to your GitHub repository
   - Click **Settings** (top menu)
   - In the left sidebar, expand **Secrets and variables** → **Actions**

2. **Create New Repository Secret:**
   - Click **New repository secret**
   - Set:
     - **Name:** `AZURE_CREDENTIALS`
     - **Secret:** Paste the entire JSON object from Step 2
   - Click **Add secret**

## Step 4: Verify the Setup

### Test Authentication Locally

Before running the GitHub Actions workflow, test that the service principal works:

```bash
# Login using the service principal
az login --service-principal \
  --username "<clientId>" \
  --password "<clientSecret>" \
  --tenant "<tenantId>"

# Verify you can list resource groups
az group list --output table

# Verify you can create a resource group
az group create --name "test-github-actions-rg" --location "eastus"

# Clean up test resource group
az group delete --name "test-github-actions-rg" --yes --no-wait
```

### Test GitHub Actions Workflow

1. **Trigger a workflow manually:**
   - Go to **Actions** tab in GitHub
   - Select **Test Bicep Template for Enterprise**
   - Click **Run workflow** → **Run workflow**

2. **Monitor the execution:**
   - Watch the **Azure Login** step to confirm authentication succeeds
   - Check that resource groups are created successfully

## Required Azure Permissions

The service principal needs the following permissions:

### Subscription-Level Permissions (RBAC)
- **Contributor** role on the subscription
  - Allows creating/deleting resource groups
  - Allows deploying ARM/Bicep templates
  - Allows managing VMs, networks, storage, etc.

### Why Contributor Role?

The GitHub Actions workflows perform these operations:
- ✅ Create resource groups (`az group create`)
- ✅ Delete resource groups (`az group delete`)
- ✅ Deploy ARM templates (`az deployment group create`)
- ✅ Create virtual machines, networks, load balancers, etc.
- ✅ Query deployment outputs
- ✅ Compile Bicep templates (`az bicep build` - no Azure permissions needed)

**Contributor** role provides all necessary permissions for these operations.

### Alternative: Reader + Resource Group Contributor

For tighter security, you can:
1. Assign **Reader** at subscription level
2. Pre-create resource groups
3. Assign **Contributor** on specific resource groups only

However, this approach doesn't work well with the dynamic resource group naming in the workflows (`ghactions-rg-<timestamp>-<run-id>`).

## Security Best Practices

### Credential Rotation
- **Rotate client secrets every 12 months** (or per your security policy)
- Set expiration reminders for client secrets
- Update the GitHub secret when rotating

### Principle of Least Privilege
- The Contributor role is scoped to the subscription used for testing
- Consider using a dedicated **non-production subscription** for GitHub Actions testing
- Never use production subscriptions for automated testing

### Secret Management
- **Never** commit the credentials JSON to source control
- **Never** print or log the credentials in workflow runs
- Store the credentials in a secure password manager
- Limit who has access to modify GitHub repository secrets

### Monitoring
- Enable Azure Activity Log monitoring for the service principal
- Set up alerts for unusual activity (e.g., resource creation in unexpected regions)
- Periodically review service principal permissions

## Troubleshooting

### Error: "AuthorizationFailed" when creating service principal

**Full error:** `The client 'user@domain.com' with object id '...' has an authorization with ABAC condition that is not fulfilled to perform action 'Microsoft.Authorization/roleAssignments/write'`

**Cause:** Your Azure account doesn't have permission to assign roles at the subscription level (requires Owner or User Access Administrator role).

**Solutions:**

1. **Use the automated script** - It detects this and creates the service principal without role assignment:
   ```bash
   ./scripts/setup-azure-credentials.sh
   ```
   Then ask an administrator to assign the Contributor role.

2. **Manual workaround** - Create without role assignment:
   ```bash
   az ad sp create-for-rbac \
     --name "github-actions-neo4j-deploy" \
     --skip-assignment \
     --json-auth
   ```

3. **Ask an administrator** to either:
   - Grant you Owner/User Access Administrator role on the subscription
   - Run the service principal creation command for you
   - Assign Contributor role to the service principal after you create it:
     ```bash
     az role assignment create \
       --assignee "<APP_ID>" \
       --role "Contributor" \
       --scope "/subscriptions/<SUBSCRIPTION_ID>"
     ```

### Error: "No subscription found"
- Verify `subscriptionId` in the JSON matches your Azure subscription
- Ensure the service principal has access to the subscription

### Error: "Insufficient privileges to complete the operation"
- Check that the service principal has **Contributor** role on the subscription
- Role assignments can take 5-10 minutes to propagate

### Error: "AADSTS7000215: Invalid client secret is provided"
- The client secret has expired or is incorrect
- Create a new client secret and update the GitHub secret

### Error: "azure/login@v2 failed"
- Verify the JSON format is exact (no extra whitespace, valid JSON)
- Ensure all required fields are present
- Check that the secret name is exactly `AZURE_CREDENTIALS`

### Verify JSON Format
Test your credentials JSON is valid:
```bash
echo '<paste-json-here>' | jq .
```

## Additional Resources

- [Azure Login Action Documentation](https://github.com/Azure/login)
- [Azure Service Principal Documentation](https://learn.microsoft.com/en-us/azure/active-directory/develop/app-objects-and-service-principals)
- [GitHub Actions Secrets](https://docs.github.com/en/actions/security-guides/encrypted-secrets)
- [Azure RBAC Roles](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles)

## Maintenance Schedule

Recommended maintenance tasks:

| Task | Frequency | Action |
|------|-----------|--------|
| Rotate client secret | Every 12 months | Create new secret, update GitHub |
| Review permissions | Quarterly | Verify Contributor role is still needed |
| Audit service principal usage | Monthly | Review Azure Activity Logs |
| Test workflow authentication | After rotation | Run manual workflow dispatch |

## Support

For issues with:
- **Azure authentication:** Contact your Azure administrator
- **GitHub Actions workflow:** Open an issue in this repository
- **Entra ID setup:** Refer to [Microsoft Entra ID documentation](https://learn.microsoft.com/en-us/entra/identity/)
