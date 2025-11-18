#!/bin/bash

echo "========================================="
echo "Checking Your Azure Permissions"
echo "========================================="
echo ""

# Get current user info
echo "=== Your Azure Account ==="
USER_ID=$(az ad signed-in-user show --query id -o tsv 2>/dev/null)
USER_UPN=$(az ad signed-in-user show --query userPrincipalName -o tsv 2>/dev/null)
USER_NAME=$(az ad signed-in-user show --query displayName -o tsv 2>/dev/null)
TENANT_ID=$(az account show --query tenantId -o tsv)

echo "Name: $USER_NAME"
echo "Email: $USER_UPN"
echo "Object ID: $USER_ID"
echo "Tenant ID: $TENANT_ID"
echo ""

# Check Azure AD Directory Roles
echo "=== Your Azure AD Directory Roles ==="
AD_ROLES=$(az rest --method GET --url "https://graph.microsoft.com/v1.0/me/memberOf" --query "value[?('@odata.type' == '#microsoft.graph.directoryRole')].displayName" -o tsv 2>/dev/null)

if [ -z "$AD_ROLES" ]; then
    echo "❌ No Azure AD Directory Roles found"
    echo ""
    echo "You need one of these Azure AD roles to create service principals:"
    echo "  • Application Administrator"
    echo "  • Application Developer"
    echo "  • Cloud Application Administrator"
    echo "  • Global Administrator"
else
    echo "✓ You have these Azure AD roles:"
    echo "$AD_ROLES" | while read -r role; do
        echo "  • $role"
    done
fi
echo ""

# Check subscription-level roles
echo "=== Your Subscription Roles ==="
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)

echo "Subscription: $SUBSCRIPTION_NAME"
echo "ID: $SUBSCRIPTION_ID"
echo ""

SUB_ROLES=$(az role assignment list --assignee "$USER_ID" --scope "/subscriptions/$SUBSCRIPTION_ID" --query "[].roleDefinitionName" -o tsv)

if [ -z "$SUB_ROLES" ]; then
    echo "❌ No subscription roles found"
else
    echo "✓ You have these subscription roles:"
    echo "$SUB_ROLES" | while read -r role; do
        echo "  • $role"
    done
fi
echo ""

# Check if user can create service principals
echo "=== Testing Service Principal Creation Permission ==="
echo "Attempting to check app registration permissions..."

# Try to list app registrations as a test
CAN_LIST=$(az ad app list --filter "displayName eq 'test-permission-check-12345'" --query "[0].appId" -o tsv 2>&1)

if [[ "$CAN_LIST" == *"Insufficient privileges"* ]]; then
    echo "❌ Cannot read app registrations (insufficient privileges)"
    HAS_APP_PERMS="NO"
elif [[ "$CAN_LIST" == *"Authorization_RequestDenied"* ]]; then
    echo "❌ Cannot read app registrations (authorization denied)"
    HAS_APP_PERMS="NO"
else
    echo "✓ Can read app registrations"
    HAS_APP_PERMS="YES"
fi
echo ""

# Summary and recommendations
echo "========================================="
echo "Summary & Recommendations"
echo "========================================="
echo ""

# Check if they have required roles
HAS_AD_ADMIN=false
if echo "$AD_ROLES" | grep -qiE "(Application Administrator|Application Developer|Cloud Application Administrator|Global Administrator)"; then
    HAS_AD_ADMIN=true
fi

HAS_SUB_ADMIN=false
if echo "$SUB_ROLES" | grep -qiE "(Owner|Contributor)"; then
    HAS_SUB_ADMIN=true
fi

echo "Required Permissions:"
echo ""
echo "1. Azure AD Role (for creating service principals):"
if [ "$HAS_AD_ADMIN" = true ]; then
    echo "   ✓ YOU HAVE THIS"
else
    echo "   ❌ YOU NEED THIS"
    echo "   Required: Application Developer (minimum) or Application Administrator"
fi
echo ""

echo "2. Subscription Role (for deploying resources):"
if [ "$HAS_SUB_ADMIN" = true ]; then
    echo "   ✓ YOU HAVE THIS"
else
    echo "   ❌ YOU NEED THIS"
    echo "   Required: Contributor (minimum) or Owner"
fi
echo ""

# Generate request message
echo "========================================="
echo "Request Message for Your Admin"
echo "========================================="
echo ""

cat > admin-permission-request.txt << EOF
Subject: Azure AD Permission Request - GitHub Actions Service Principal

Hello,

I need to set up automated deployments for the Neo4j Azure project using GitHub Actions. To do this, I need to create a service principal for authentication.

Current Status:
• Name: $USER_NAME
• Email: $USER_UPN
• User Object ID: $USER_ID
• Subscription: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)

What I Need:

1. Azure AD Role Assignment
   Please grant me ONE of these roles in Azure Active Directory:

   Option A (Recommended): Application Developer
   - Minimum permissions needed
   - Can create and manage app registrations
   - Cannot manage other users' apps

   OR

   Option B: Application Administrator
   - Can manage all app registrations
   - More permissions than needed but commonly used

   How to grant this:
   • Azure Portal → Azure Active Directory → Roles and administrators
   • Search for "Application Developer" or "Application Administrator"
   • Click the role → Add assignments → Add my user

2. Verify Subscription Access
   Please confirm I have "Contributor" or "Owner" role on subscription:
   "$SUBSCRIPTION_NAME" ($SUBSCRIPTION_ID)

Purpose:
This will allow me to create a service principal named "github-actions-neo4j-deploy"
that GitHub Actions will use to deploy Neo4j resources to Azure automatically.

Security Note:
The service principal will only have "Contributor" access scoped to the
specific subscription, following least-privilege principles.

Please let me know once this is configured, and I can proceed with the setup.

Thank you!
$USER_NAME
EOF

cat admin-permission-request.txt
echo ""
echo "========================================="
echo ""
echo "This message has been saved to: admin-permission-request.txt"
echo ""

if [ "$HAS_AD_ADMIN" = true ] && [ "$HAS_SUB_ADMIN" = true ]; then
    echo "✓ You appear to have all required permissions!"
    echo "  If you're still getting errors, there may be additional tenant-level restrictions."
    echo "  Send the request message to your admin to investigate."
else
    echo "Send the message above to your Azure AD administrator."
fi
echo ""
