#!/bin/bash
set -euo pipefail

# Azure Credentials Setup Script for GitHub Actions
# This script creates a service principal and outputs the credentials needed for GitHub Secrets

echo "========================================="
echo "Azure Credentials Setup for GitHub Actions"
echo "========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# Check if Azure CLI is installed
echo "Checking prerequisites..."
if ! command -v az &> /dev/null; then
    print_error "Azure CLI is not installed"
    echo ""
    echo "Install Azure CLI:"
    echo "  macOS:   brew install azure-cli"
    echo "  Linux:   curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash"
    echo "  Windows: winget install Microsoft.AzureCLI"
    echo ""
    exit 1
fi
print_success "Azure CLI is installed"

# Check if jq is installed (for JSON formatting)
if ! command -v jq &> /dev/null; then
    print_warning "jq is not installed (optional, but recommended for pretty JSON)"
    echo "  Install: brew install jq  (macOS) or  sudo apt install jq  (Linux)"
    echo ""
fi

# Check Azure login status
echo ""
echo "Checking Azure login status..."
if ! az account show &> /dev/null; then
    print_warning "Not logged in to Azure"
    echo ""
    echo "Logging in to Azure..."
    az login

    if [ $? -ne 0 ]; then
        print_error "Azure login failed"
        exit 1
    fi
fi
print_success "Logged in to Azure"

# Get current subscription info
echo ""
echo "Getting subscription information..."
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)

if [ -z "$SUBSCRIPTION_ID" ]; then
    print_error "Could not get subscription ID"
    exit 1
fi

print_success "Found subscription: $SUBSCRIPTION_NAME"
print_info "Subscription ID: $SUBSCRIPTION_ID"

# Confirm subscription
echo ""
echo "================================================"
echo "Current Azure Subscription:"
echo "  Name: $SUBSCRIPTION_NAME"
echo "  ID:   $SUBSCRIPTION_ID"
echo "================================================"
echo ""
read -p "Is this the correct subscription? (y/n): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    print_warning "Operation cancelled by user"
    echo ""
    echo "To switch subscriptions, run:"
    echo "  az account list --output table"
    echo "  az account set --subscription <subscription-id>"
    echo ""
    exit 0
fi

# Set service principal name
SP_NAME="github-actions-neo4j-deploy"
echo ""
print_info "Service Principal Name: $SP_NAME"

# Check if service principal already exists
echo ""
echo "Checking if service principal already exists..."
EXISTING_SP=$(az ad sp list --display-name "$SP_NAME" --query "[].appId" -o tsv)

if [ -n "$EXISTING_SP" ]; then
    print_warning "Service principal '$SP_NAME' already exists (App ID: $EXISTING_SP)"
    echo ""
    read -p "Do you want to delete and recreate it? (y/n): " -n 1 -r
    echo ""

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo ""
        echo "Deleting existing service principal..."
        az ad sp delete --id "$EXISTING_SP"
        print_success "Deleted existing service principal"
    else
        print_warning "Keeping existing service principal"
        echo ""
        print_error "Cannot create credentials - service principal already exists"
        echo ""
        echo "Options:"
        echo "  1. Delete it manually: az ad sp delete --id $EXISTING_SP"
        echo "  2. Use a different name by editing this script"
        echo "  3. Retrieve existing credentials (if you have them saved)"
        echo ""
        exit 1
    fi
fi

# Create service principal
echo ""
echo "Creating service principal with Contributor role..."
echo "This may take a few seconds..."
echo ""

# Create the service principal and capture output
SP_OUTPUT=$(az ad sp create-for-rbac \
    --name "$SP_NAME" \
    --role contributor \
    --scopes "/subscriptions/$SUBSCRIPTION_ID" \
    --sdk-auth 2>&1)

if [ $? -ne 0 ]; then
    print_error "Failed to create service principal"
    echo ""
    echo "Error output:"
    echo "$SP_OUTPUT"
    exit 1
fi

print_success "Service principal created successfully"

# Extract client ID for verification
CLIENT_ID=$(echo "$SP_OUTPUT" | grep -o '"clientId": "[^"]*"' | cut -d'"' -f4)
TENANT_ID=$(echo "$SP_OUTPUT" | grep -o '"tenantId": "[^"]*"' | cut -d'"' -f4)

print_info "Client ID: $CLIENT_ID"
print_info "Tenant ID: $TENANT_ID"

# Verify role assignment
echo ""
echo "Verifying role assignment..."
sleep 3  # Wait a moment for Azure to propagate

ROLE_CHECK=$(az role assignment list --assignee "$CLIENT_ID" --query "[?roleDefinitionName=='Contributor'].roleDefinitionName" -o tsv)

if [ "$ROLE_CHECK" == "Contributor" ]; then
    print_success "Contributor role verified"
else
    print_warning "Could not verify Contributor role (may need a moment to propagate)"
fi

# Save credentials to file
OUTPUT_FILE="azure-credentials.json"
echo ""
echo "Saving credentials to file: $OUTPUT_FILE"
echo "$SP_OUTPUT" > "$OUTPUT_FILE"

# Pretty print if jq is available
if command -v jq &> /dev/null; then
    jq '.' "$OUTPUT_FILE" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "$OUTPUT_FILE"
    print_success "Credentials saved and formatted"
else
    print_success "Credentials saved"
fi

# Display credentials (with warning)
echo ""
echo "========================================="
echo "⚠️  CREDENTIALS (KEEP SECURE!)"
echo "========================================="
echo ""

if command -v jq &> /dev/null; then
    cat "$OUTPUT_FILE" | jq '.'
else
    cat "$OUTPUT_FILE"
fi

echo ""
echo "========================================="
echo ""

# Instructions for GitHub
echo ""
echo "================================================"
print_success "Setup Complete!"
echo "================================================"
echo ""
echo "Next Steps:"
echo ""
echo "1. Copy the JSON credentials above (or from $OUTPUT_FILE)"
echo ""
echo "2. Go to your GitHub repository:"
echo "   https://github.com/YOUR-ORG/azure-neo4j-modernize/settings/secrets/actions"
echo ""
echo "3. Click 'New repository secret'"
echo ""
echo "4. Create secret:"
echo "   Name:  AZURE_CREDENTIALS"
echo "   Value: <paste the entire JSON from above>"
echo ""
echo "5. Click 'Add secret'"
echo ""
echo "================================================"
echo ""

# Security warnings
print_warning "SECURITY REMINDERS:"
echo ""
echo "  • Store $OUTPUT_FILE securely (contains sensitive credentials)"
echo "  • Do NOT commit $OUTPUT_FILE to git"
echo "  • Consider deleting $OUTPUT_FILE after copying to GitHub"
echo "  • The clientSecret cannot be retrieved again"
echo "  • Rotate credentials periodically for security"
echo ""

# Additional info
echo "================================================"
echo "Service Principal Information:"
echo "================================================"
echo "  Name:           $SP_NAME"
echo "  Client ID:      $CLIENT_ID"
echo "  Tenant ID:      $TENANT_ID"
echo "  Subscription:   $SUBSCRIPTION_ID"
echo "  Role:           Contributor"
echo "  Scope:          /subscriptions/$SUBSCRIPTION_ID"
echo "================================================"
echo ""

# Cleanup instructions
echo "To delete this service principal later:"
echo "  az ad sp delete --id $CLIENT_ID"
echo ""

print_success "All done! Add the credentials to GitHub Secrets and you're ready to go."
echo ""
