# Neo4j Enterprise Standard Deployment Modernization

**Date:** 2025-11-17
**Focus:** Simple migration to modern Azure practices for Enterprise standard (standalone) deployment
**Approach:** Get it working first, optimize later

---

## What's Already Done

✅ Enterprise Bicep template created (mainTemplate.bicep)
✅ Bicep compiles with zero errors and warnings
✅ Deploy and archive scripts updated
✅ Linter and pre-commit hooks configured

---

## What Needs to Be Done

Three simple phases to modernize the Enterprise standard deployment:

### Phase 1: Replace Bash Scripts with Cloud-Init (2 weeks)

**Goal:** Stop downloading bash scripts from GitHub. Embed cloud-init configuration directly in the Bicep template.

**Current state:** Template downloads and runs bash scripts via CustomScript extension
**Target state:** Template uses cloud-init with YAML embedded in Bicep

**Tasks:**
- Create `scripts/neo4j-enterprise/cloud-init/standalone.yaml`
  - Mount and format data disk
  - Install Neo4j package
  - Write Neo4j configuration file
  - Start Neo4j service
- Update `mainTemplate.bicep`:
  - Remove CustomScript extension
  - Add cloud-init using `loadTextContent('cloud-init/standalone.yaml')`
  - Remove `scriptsBaseUrl` variable
  - Pass admin password and other parameters to cloud-init
- Test standalone deployment (nodeCount=1)
- Verify Neo4j starts and is accessible via Browser and Bolt

**Done when:** Can deploy single-node Neo4j without any external script downloads

---

### Phase 2: Azure Key Vault for Passwords (1 week)

**Goal:** Stop passing passwords as template parameters. Use Azure Key Vault instead.

**Current state:** Password passed as @secure() parameter
**Target state:** Password stored in Key Vault, VMs retrieve via managed identity

**Tasks:**
- Update `deploy.sh`:
  - Check if Key Vault exists, create if not
  - Generate random password if secret doesn't exist
  - Store password in Key Vault
  - Pass Key Vault info to deployment (not password)
- Update `mainTemplate.bicep`:
  - Remove `@secure() param adminPassword`
  - Add `param keyVaultName string`
  - Add `param secretName string = 'neo4j-password'`
  - Grant VMSS managed identity access to Key Vault
- Update `cloud-init/standalone.yaml`:
  - Retrieve password from Key Vault using managed identity
  - Use password to configure Neo4j
- Test deployment with Key Vault

**Done when:** Password never appears in parameters, VMs get password from Key Vault

---

### Phase 3: Test and Document (1 week)

**Goal:** Make sure it works and others can use it.

**Tasks:**
- Deploy and validate standalone Neo4j 5
- Verify connection via Neo4j Browser
- Verify connection via Bolt protocol
- Update README.md with new deployment instructions
- Document Key Vault setup
- Update GitHub Actions workflow to use new approach
- Create marketplace archive

**Done when:** Someone else can follow the README and deploy successfully

---

## Timeline

| Phase | Duration | What Gets Done |
|-------|----------|----------------|
| Phase 1 | 2 weeks | Cloud-init replaces bash scripts |
| Phase 2 | 1 week | Key Vault replaces password parameters |
| Phase 3 | 1 week | Testing and documentation |
| **Total** | **4 weeks** | **Working modern deployment** |

---

## Success Criteria

The migration is complete when:

1. ✅ Bicep template has no external script dependencies
2. ✅ Cloud-init YAML is embedded in template using `loadTextContent()`
3. ✅ No passwords in parameter files or templates
4. ✅ VMs retrieve passwords from Key Vault via managed identity
5. ✅ Single-node Neo4j 5 deploys successfully
6. ✅ Neo4j Browser and Bolt connections work
7. ✅ Documentation allows others to deploy

---

## What's NOT Included (Do Later)

- ❌ Cluster deployments (multi-node)
- ❌ Read replicas
- ❌ Neo4j 4.4 support
- ❌ Plugin testing (GDS, Bloom)
- ❌ Performance testing
- ❌ Different VM sizes
- ❌ Community edition
- ❌ Resource tagging
- ❌ Advanced monitoring
- ❌ Template Specs
- ❌ ARM-TTK validation

**These can be added incrementally after the basic migration works.**

---

## Key Files to Change

```
Phase 1 - Cloud-Init:
  - Create: scripts/neo4j-enterprise/cloud-init/standalone.yaml
  - Update: marketplace/neo4j-enterprise/mainTemplate.bicep

Phase 2 - Key Vault:
  - Update: marketplace/neo4j-enterprise/deploy.sh
  - Update: marketplace/neo4j-enterprise/mainTemplate.bicep
  - Update: scripts/neo4j-enterprise/cloud-init/standalone.yaml

Phase 3 - Testing:
  - Update: README.md
  - Update: .github/workflows/enterprise.yml
  - Validate: Archive creation works
```

---

## Cloud-Init Example Structure

The cloud-init YAML should do these steps in order:

1. **Mount disk:**
   ```yaml
   - Mount /dev/sdc to /var/lib/neo4j
   - Format if needed
   ```

2. **Install Neo4j:**
   ```yaml
   - Add Neo4j repository
   - Install neo4j-enterprise package
   ```

3. **Configure Neo4j:**
   ```yaml
   - Write /etc/neo4j/neo4j.conf
   - Set initial password
   - Set listen addresses
   ```

4. **Start service:**
   ```yaml
   - Enable neo4j service
   - Start neo4j service
   ```

---

## Key Vault Integration Pattern

```bash
# In deploy.sh
VAULT_NAME="neo4j-vault-${UNIQUE_ID}"
SECRET_NAME="neo4j-password"

# Create vault if needed
az keyvault create --name $VAULT_NAME ...

# Generate and store password
PASSWORD=$(openssl rand -base64 32)
az keyvault secret set --vault-name $VAULT_NAME --name $SECRET_NAME --value $PASSWORD

# Deploy template with vault info (not password)
az deployment group create \
  --parameters keyVaultName=$VAULT_NAME secretName=$SECRET_NAME
```

```bicep
// In mainTemplate.bicep
param keyVaultName string
param secretName string

// Grant managed identity access to vault
resource keyVaultAccess 'Microsoft.KeyVault/vaults/accessPolicies@2023-02-01' = {
  // ... grant 'get' permission to VMSS identity
}
```

```yaml
# In cloud-init YAML
runcmd:
  - PASSWORD=$(az keyvault secret show --name ${SECRET_NAME} --vault-name ${VAULT_NAME} --query value -o tsv)
  - neo4j-admin set-initial-password "$PASSWORD"
```

---

**Last Updated:** 2025-11-17
**Next Step:** Start Phase 1 - Create cloud-init YAML for standalone deployment
