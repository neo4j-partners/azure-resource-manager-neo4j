# Scripts Directory

## Azure Credentials Setup

### Quick Start

Run the setup script to create Azure credentials for GitHub Actions:

```bash
./scripts/setup-azure-credentials.sh
```

### What It Does

The script will:
1. ✅ Check if Azure CLI is installed
2. ✅ Login to Azure (if needed)
3. ✅ Display your current subscription
4. ✅ Ask for confirmation
5. ✅ Create a service principal named `github-actions-neo4j-deploy`
6. ✅ Grant it `Contributor` role on your subscription
7. ✅ Generate credentials in the correct format
8. ✅ Save credentials to `azure-credentials.json`
9. ✅ Display instructions for adding to GitHub Secrets

### Prerequisites

- **Azure CLI** installed ([install guide](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli))
- **jq** (optional, for pretty JSON formatting)
  ```bash
  # macOS
  brew install jq

  # Linux
  sudo apt install jq
  ```
- Azure subscription with permissions to create service principals

### Usage

```bash
# Navigate to project root
cd azure-neo4j-modernize

# Run the setup script
./scripts/setup-azure-credentials.sh

# Follow the prompts
```

### Output

The script creates:
- **azure-credentials.json** - Your service principal credentials (⚠️ keep secure!)

Example output:
```json
{
  "clientId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "clientSecret": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
  "subscriptionId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "tenantId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "activeDirectoryEndpointUrl": "https://login.microsoftonline.com",
  "resourceManagerEndpointUrl": "https://management.azure.com/",
  ...
}
```

### Adding to GitHub

1. Copy the entire JSON from `azure-credentials.json`
2. Go to: `https://github.com/YOUR-ORG/azure-neo4j-modernize/settings/secrets/actions`
3. Click "New repository secret"
4. Name: `AZURE_CREDENTIALS`
5. Value: Paste the JSON
6. Click "Add secret"

### Security

⚠️ **Important:**
- The `azure-credentials.json` file contains sensitive credentials
- It is already added to `.gitignore` to prevent accidental commits
- Store it securely or delete it after adding to GitHub
- The `clientSecret` cannot be retrieved again if lost
- Consider rotating credentials periodically

### Troubleshooting

**Error: "Azure CLI is not installed"**
- Install Azure CLI: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli

**Error: "Not logged in to Azure"**
- The script will prompt you to login automatically

**Error: "Service principal already exists"**
- The script will offer to delete and recreate it
- Or delete manually: `az ad sp delete --id <client-id>`

**Error: "Insufficient privileges"**
- You need permissions to create service principals in Azure AD
- Contact your Azure administrator

### Managing Service Principals

**List service principals:**
```bash
az ad sp list --display-name "github-actions-neo4j-deploy" --output table
```

**Delete service principal:**
```bash
# Get the client ID from azure-credentials.json or script output
az ad sp delete --id <client-id>
```

**Verify role assignment:**
```bash
az role assignment list --assignee <client-id> --output table
```

### Alternative: Manual Setup

If you prefer not to use the script, follow the manual instructions in the main repository documentation.

### Support

For issues or questions, see:
- [Azure CLI Documentation](https://docs.microsoft.com/en-us/cli/azure/)
- [GitHub Actions Secrets](https://docs.github.com/en/actions/security-guides/encrypted-secrets)
- [Azure Service Principals](https://docs.microsoft.com/en-us/azure/active-directory/develop/app-objects-and-service-principals)
