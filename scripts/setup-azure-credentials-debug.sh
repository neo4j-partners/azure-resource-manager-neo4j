#!/bin/bash
# Debug version - shows each step clearly

echo "=== STEP 1: Checking Azure CLI ==="
if ! command -v az &> /dev/null; then
    echo "ERROR: Azure CLI not found"
    exit 1
fi
echo "✓ Azure CLI found"
echo ""

echo "=== STEP 2: Checking Azure login ==="
if ! az account show &> /dev/null; then
    echo "Not logged in. Running 'az login'..."
    az login
else
    echo "✓ Already logged in"
fi
echo ""

echo "=== STEP 3: Getting subscription ==="
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
echo "Subscription: $SUBSCRIPTION_NAME"
echo "ID: $SUBSCRIPTION_ID"
echo ""

echo "=== STEP 4: Creating service principal ==="
echo "This will create: github-actions-neo4j-deploy"
echo "With role: Contributor"
echo "On subscription: $SUBSCRIPTION_ID"
echo ""

# Just create it without prompts for debugging
SP_OUTPUT=$(az ad sp create-for-rbac \
    --name "github-actions-neo4j-deploy" \
    --role contributor \
    --scopes "/subscriptions/$SUBSCRIPTION_ID" \
    --sdk-auth 2>&1)

RESULT=$?
echo ""

if [ $RESULT -ne 0 ]; then
    echo "ERROR: Failed to create service principal"
    echo ""
    echo "Error message:"
    echo "$SP_OUTPUT"
    echo ""

    # Check if it already exists
    EXISTING=$(az ad sp list --display-name "github-actions-neo4j-deploy" --query "[].appId" -o tsv)
    if [ -n "$EXISTING" ]; then
        echo "Service principal already exists with ID: $EXISTING"
        echo ""
        echo "To delete it and try again:"
        echo "  az ad sp delete --id $EXISTING"
        echo ""
    fi
    exit 1
fi

echo "✓ Service principal created"
echo ""

echo "=== STEP 5: Saving credentials ==="
echo "$SP_OUTPUT" > azure-credentials.json
echo "✓ Saved to: azure-credentials.json"
echo ""

echo "=== CREDENTIALS (copy this entire JSON) ==="
cat azure-credentials.json
echo ""
echo "=== END CREDENTIALS ==="
echo ""

echo "✓ DONE! Now add to GitHub Secrets:"
echo "  1. Go to: Settings → Secrets and variables → Actions"
echo "  2. New repository secret"
echo "  3. Name: AZURE_CREDENTIALS"
echo "  4. Value: <paste JSON from above>"
echo ""
