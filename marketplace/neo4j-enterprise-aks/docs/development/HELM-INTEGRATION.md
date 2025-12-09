# Helm Integration Technical Reference

Technical documentation for developers working on the Helm chart integration in `helm-deployment.bicep`.

## Overview

The Neo4j AKS deployment uses the **official Neo4j Helm chart** (`neo4j/neo4j`) rather than custom Kubernetes resources. This reduces maintenance burden and ensures compatibility with Neo4j best practices.

**Implementation:** `modules/helm-deployment.bicep`
**Chart Version:** 5.24.0 (pinned)
**Chart Repository:** https://helm.neo4j.com/neo4j
**Official Docs:** https://github.com/neo4j/helm-charts

## Architecture

```
main.bicep
  ↓
neo4j-app.bicep
  ↓
helm-deployment.bicep
  ↓
Azure deploymentScripts resource
  ↓
Bash script that runs:
  - helm repo add
  - helm upgrade --install
  ↓
Neo4j Helm Chart
  ↓
Kubernetes Resources (StatefulSet, Services, etc.)
```

## helm-deployment.bicep Structure

### deploymentScripts Resource

Uses Azure `Microsoft.Resources/deploymentScripts@2023-08-01` to run Helm commands:

```bicep
resource helmInstall 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'helm-install-${uniqueString(resourceGroup().id, namespaceName, releaseName)}'
  location: location
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identityId}': {}
    }
  }
  properties: {
    azCliVersion: '2.50.0'
    timeout: 'PT30M'
    environmentVariables: [...]
    scriptContent: '''...'''
  }
}
```

**Why deploymentScripts?**
- Runs in Azure-managed container
- Has Azure CLI and kubectl pre-installed
- Supports managed identity authentication
- Provides output capture for Bicep
- Better error handling than custom scripts

### Environment Variables

Parameters passed to script via environment variables:

```bicep
environmentVariables: [
  {
    name: 'AKS_CLUSTER_NAME'
    value: aksClusterName
  }
  {
    name: 'NEO4J_PASSWORD'
    secureValue: adminPassword  // Secure parameters
  }
  // ... more variables
]
```

**Secure values:** Use `secureValue` for passwords and secrets.

### Script Content

Embedded bash script that:
1. Installs kubectl and Helm
2. Gets AKS credentials
3. Adds Neo4j Helm repository
4. Builds Helm command with proper parameter mapping
5. Executes Helm install
6. Waits for deployment
7. Extracts external IP
8. Outputs results for Bicep

## Critical Parameter Mappings

These are the **most important** corrections from the implementation:

### 1. Storage Configuration

**❌ WRONG:**
```bash
--set volumes.data.dynamic.storage=32Gi
```

**✅ CORRECT:**
```bash
--set volumes.data.dynamic.requests.storage=32Gi
```

**Why:** The Helm chart uses Kubernetes PVC structure with `requests.storage`, not just `storage`.

**Code location:** helm-deployment.bicep:259-260

### 2. Resource Configuration

**❌ WRONG:**
```bash
--set resources.cpu=2000m
--set resources.memory=8Gi
```

**✅ CORRECT:**
```bash
--set neo4j.resources.cpu=2000m
--set neo4j.resources.memory=8Gi
```

**Why:** Resources are nested under `neo4j.resources` in the chart structure.

**Code location:** helm-deployment.bicep:264-265

### 3. Memory Configuration

**❌ WRONG:**
```bash
--set-json config='{"server.memory.heap.initial_size": "4G"}'
```

**✅ CORRECT:**
```bash
--set config.server\.memory\.heap\.initial_size=4G
--set config.server\.memory\.heap\.max_size=4G
--set config.server\.memory\.pagecache\.size=3G
```

**Why:** Using `--set-json` with nested structures causes parsing issues. Use escaped dots instead.

**Code location:** helm-deployment.bicep:269-271

### 4. Image Configuration

**❌ WRONG:**
```bash
--set image.repository=neo4j
--set image.tag=$NEO4J_VERSION-enterprise
```

**✅ CORRECT:**
```bash
# Let chart use defaults
# Chart automatically selects correct image based on neo4j.edition
```

**Why:** The Neo4j Helm chart has built-in logic to select the correct image based on edition and cluster configuration.

**Code location:** helm-deployment.bicep:242-246 (no image override)

## Helm Command Construction

### Dynamic Command Building

The script builds the Helm command dynamically based on parameters:

```bash
# Base command
HELM_CMD="helm upgrade --install $RELEASE_NAME $HELM_CHART_NAME"
HELM_CMD="$HELM_CMD --version $HELM_CHART_VERSION"
HELM_CMD="$HELM_CMD --namespace $NAMESPACE_NAME"

# Neo4j configuration
HELM_CMD="$HELM_CMD --set neo4j.name=$CLUSTER_NAME"
HELM_CMD="$HELM_CMD --set neo4j.password=$NEO4J_PASSWORD"

# Conditional cluster configuration
if [ "$IS_CLUSTER" == "true" ]; then
  HELM_CMD="$HELM_CMD --set neo4j.minimumClusterSize=$NODE_COUNT"
fi

# Execute
eval $HELM_CMD
```

**Why eval?** Allows dynamic command construction with proper quoting.

### Parameter Types

**Fixed parameters** (always set):
- `neo4j.name`
- `neo4j.edition`
- `neo4j.acceptLicenseAgreement`
- `neo4j.password`
- `volumes.data.mode`
- `volumes.data.dynamic.storageClassName`
- `volumes.data.dynamic.requests.storage`
- `neo4j.resources.cpu`
- `neo4j.resources.memory`
- `services.neo4j.enabled`
- `services.neo4j.spec.type`

**Conditional parameters** (based on configuration):
- `neo4j.minimumClusterSize` (only if nodeCount >= 3)
- `env.NEO4JLABS_PLUGINS` (future: if plugins enabled)

## Output Extraction

### Waiting for External IP

The script waits up to 10 minutes for LoadBalancer to get external IP:

```bash
EXTERNAL_IP=""
for i in {1..60}; do
  EXTERNAL_IP=$(kubectl get service ${RELEASE_NAME} -n $NAMESPACE_NAME \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
  if [ -n "$EXTERNAL_IP" ] && [ "$EXTERNAL_IP" != "null" ]; then
    echo "External IP assigned: $EXTERNAL_IP"
    break
  fi
  sleep 10
done
```

### Outputs for Bicep

Results are written to `$AZ_SCRIPTS_OUTPUT_PATH` as JSON:

```bash
cat > $AZ_SCRIPTS_OUTPUT_PATH <<EOF
{
  "releaseName": "$RELEASE_NAME",
  "releaseStatus": "$RELEASE_STATUS",
  "helmVersion": "$HELM_VERSION",
  "externalIp": "$EXTERNAL_IP",
  "browserUrl": "http://$EXTERNAL_IP:7474",
  "boltUri": "neo4j://$EXTERNAL_IP:7687"
}
EOF
```

Bicep can then read these outputs:

```bicep
output externalIp string = helmInstall.properties.outputs.externalIp
output browserUrl string = helmInstall.properties.outputs.browserUrl
```

## Chart Version Management

### Pinning Strategy

**Current:** Pinned to `5.24.0`

```bicep
var helmChartVersion = '5.24.0'  // Pinned version
```

**Why pinned?**
- Predictable deployments
- Prevents breaking changes from chart updates
- Easier troubleshooting

**When to update:**
1. Test new chart version in development
2. Verify parameter compatibility
3. Update `helmChartVersion` variable
4. Update documentation
5. Test deployment end-to-end

### Chart Version Compatibility

| Chart Version | Neo4j Version | Status |
|---------------|---------------|--------|
| 5.24.0 | 5.x | ✅ Current |
| 5.23.x | 5.x | ⚠️ Older |

**Check available versions:**
```bash
helm repo update
helm search repo neo4j/neo4j --versions
```

## Common Implementation Mistakes

### Mistake 1: Using --set-json for Nested Config

**Problem:**
```bash
--set-json config='{"server.memory.heap.initial_size": "4G"}'
```

**Error:** Helm parsing issues with nested JSON

**Solution:**
```bash
--set config.server\.memory\.heap\.initial_size=4G
```

### Mistake 2: Not Escaping Dots in Config Keys

**Problem:**
```bash
--set config.server.memory.heap.initial_size=4G
```

**Error:** Helm interprets as nested YAML structure

**Solution:**
```bash
--set config.server\.memory\.heap\.initial_size=4G
```

### Mistake 3: Overriding Default Image

**Problem:**
```bash
--set image.repository=neo4j
--set image.tag=5-enterprise
```

**Issue:** Conflicts with chart's automatic image selection

**Solution:** Don't set image parameters; let chart choose

### Mistake 4: Wrong Storage Parameter Path

**Problem:**
```bash
--set volumes.data.dynamic.storage=32Gi
```

**Error:** PVC creation fails (unknown field)

**Solution:**
```bash
--set volumes.data.dynamic.requests.storage=32Gi
```

## Testing Helm Changes

### Local Helm Testing

Before modifying `helm-deployment.bicep`, test Helm command manually:

```bash
# Get AKS credentials
az aks get-credentials --name <cluster> --resource-group <rg>

# Test with dry-run
helm install neo4j-test neo4j/neo4j \
  --version 5.24.0 \
  --namespace neo4j-test \
  --create-namespace \
  --set neo4j.name=neo4j-standalone \
  --set neo4j.edition=enterprise \
  --set neo4j.acceptLicenseAgreement=eval \
  --set neo4j.password=TestPassword123! \
  --set volumes.data.mode=dynamic \
  --set volumes.data.dynamic.storageClassName=neo4j-premium \
  --set volumes.data.dynamic.requests.storage=32Gi \
  --set neo4j.resources.cpu=2000m \
  --set neo4j.resources.memory=8Gi \
  --set config.server\.memory\.heap\.initial_size=4G \
  --set config.server\.memory\.heap\.max_size=4G \
  --set config.server\.memory\.pagecache\.size=3G \
  --set services.neo4j.enabled=true \
  --set services.neo4j.spec.type=LoadBalancer \
  --dry-run --debug
```

**Check output for:**
- No errors or warnings
- Correct resource creation (StatefulSet, PVC, Service)
- Proper parameter values in generated YAML

### Deployment Script Testing

After making changes to `helm-deployment.bicep`:

1. **Deploy via Bicep:**
   ```bash
   ./deploy.sh test-helm-changes
   ```

2. **Monitor deployment script logs:**
   ```bash
   az deployment-scripts show-log \
     --resource-group test-helm-changes \
     --name helm-install-<unique-id>
   ```

3. **Check Helm release:**
   ```bash
   helm list -n neo4j
   helm get values neo4j -n neo4j
   ```

4. **Verify pods:**
   ```bash
   kubectl get pods -n neo4j
   kubectl describe pod neo4j-0 -n neo4j
   ```

## Debugging

### Deployment Script Failures

**View deployment script logs:**
```bash
az deployment-scripts show-log \
  --resource-group <rg-name> \
  --name helm-install-<unique-id>
```

**Common issues:**
- Helm repository not reachable
- Chart version doesn't exist
- Invalid Helm parameter syntax
- kubectl authentication failure

### Helm Deployment Issues

**Check Helm status:**
```bash
helm status neo4j -n neo4j
helm history neo4j -n neo4j
```

**View generated values:**
```bash
helm get values neo4j -n neo4j
helm get manifest neo4j -n neo4j
```

**Check pod events:**
```bash
kubectl describe pod neo4j-0 -n neo4j
kubectl logs neo4j-0 -n neo4j
```

### Parameter Validation

If pods won't start, verify parameters reached Neo4j:

```bash
# Check Neo4j config
kubectl exec neo4j-0 -n neo4j -- cat /var/lib/neo4j/conf/neo4j.conf

# Check memory settings specifically
kubectl exec neo4j-0 -n neo4j -- grep -i memory /var/lib/neo4j/conf/neo4j.conf
```

## Future Improvements

### Plugin Support

Add environment variable for plugins:

```bash
if [ "$PLUGINS" != "[]" ]; then
  HELM_CMD="$HELM_CMD --set env.NEO4JLABS_PLUGINS='$PLUGINS'"
fi
```

**Note:** Requires Neo4j image that supports `NEO4JLABS_PLUGINS` env var.

### Dynamic Memory Calculation

Calculate heap/pagecache based on pod memory:

```bash
# Extract memory value
MEMORY_GB=$(echo $MEMORY_REQUEST | sed 's/Gi//')

# Calculate heap (50%) and pagecache (37%)
HEAP_GB=$((MEMORY_GB / 2))
PAGECACHE_GB=$((MEMORY_GB * 37 / 100))

HELM_CMD="$HELM_CMD --set config.server\.memory\.heap\.initial_size=${HEAP_GB}G"
HELM_CMD="$HELM_CMD --set config.server\.memory\.pagecache\.size=${PAGECACHE_GB}G"
```

### Chart Update Process

When updating to newer Helm chart version:

1. Review chart CHANGELOG
2. Test new version in dev environment
3. Verify all parameters still work
4. Update `helmChartVersion` variable
5. Update this documentation
6. Test deployment end-to-end
7. Update CHANGELOG.md

## References

- **Neo4j Helm Charts:** https://github.com/neo4j/helm-charts
- **Chart values.yaml:** https://github.com/neo4j/helm-charts/blob/master/neo4j/values.yaml
- **Neo4j K8s Docs:** https://neo4j.com/docs/operations-manual/5/kubernetes/
- **Helm Documentation:** https://helm.sh/docs/
- **Azure deploymentScripts:** https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/deployment-script-bicep

---

**Document Version:** 1.0
**Last Updated:** November 2025
**Chart Version:** neo4j/neo4j 5.24.0
