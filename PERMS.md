# Azure Permissions Request

## Slack Message (Copy-Paste)

```
I successfully created the service principal `github-actions-neo4j-deploy` (App ID: 36c18700-23db-4d51-bb46-5dda9c5cd403) for our GitHub Actions workflows, but I need help assigning it the Contributor role on the Business Development subscription. My current Contributor role doesn't include permission to assign roles to other principals. Could you either grant me the Owner role (easiest) or User Access Administrator role (more limited) so I can complete this? Alternatively, you could assign the role directly by running: `az role assignment create --assignee "36c18700-23db-4d51-bb46-5dda9c5cd403" --role "Contributor" --scope "/subscriptions/47fd4ce5-a912-480e-bb81-95fbd59bb6c5"` - whichever you prefer!
```

---

# Azure Permissions Request

## Status

I successfully created the service principal:
- **Name:** `github-actions-neo4j-deploy`
- **Application ID:** `36c18700-23db-4d51-bb46-5dda9c5cd403`
- **Purpose:** Run GitHub Actions workflows for automated Neo4j deployment testing

## What I Need

The service principal needs **Contributor** role on the **Business Development** subscription to deploy and test ARM templates.

However, I cannot assign this role myself because the Contributor role I currently have does not include permission to assign roles to other principals.

## Request

To complete the setup, I need **one** of the following on the **Business Development** subscription:

### Option 1: Grant me Owner role (Easiest)
This would allow me to assign roles and manage resources. It's the simplest solution.

```bash
# Run as administrator
az role assignment create \
  --assignee "ryan.knight@neo4j.com" \
  --role "Owner" \
  --scope "/subscriptions/47fd4ce5-a912-480e-bb81-95fbd59bb6c5"
```

### Option 2: Grant me User Access Administrator role (More Limited)
If you prefer to keep the scope more limited, this role allows me to assign roles without additional resource management permissions.

```bash
# Run as administrator
az role assignment create \
  --assignee "ryan.knight@neo4j.com" \
  --role "User Access Administrator" \
  --scope "/subscriptions/47fd4ce5-a912-480e-bb81-95fbd59bb6c5"
```

### Option 3: Assign the role yourself
If you prefer not to grant me additional permissions, you can assign the Contributor role to the service principal directly:

```bash
# Run as administrator
az role assignment create \
  --assignee "36c18700-23db-4d51-bb46-5dda9c5cd403" \
  --role "Contributor" \
  --scope "/subscriptions/47fd4ce5-a912-480e-bb81-95fbd59bb6c5"
```

## Role Comparison

| Role | Manage Resources | Assign Roles | Notes |
|------|------------------|--------------|-------|
| Contributor (current) | ✅ | ❌ | Cannot assign roles |
| User Access Administrator | ❌ | ✅ | Can only manage access |
| Owner | ✅ | ✅ | Full control |

## Background

The GitHub Actions workflows need to:
- Create and delete resource groups
- Deploy ARM/Bicep templates
- Create VMs, networks, load balancers for testing
- Validate Neo4j deployments
- Clean up resources after testing

All of these operations require the Contributor role on the service principal.
