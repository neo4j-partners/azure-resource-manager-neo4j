# Neo4j AKS Deployment Troubleshooting Guide

**Last Updated**: November 20, 2025

---

## Quick Diagnostics

### Check Deployment Status

```bash
# From repository root
cd deployments

# View all deployments
uv run neo4j-deploy status

# Check specific deployment
az deployment group show \
  --resource-group <rg-name> \
  --name main \
  --query "properties.provisioningState"
```

### Check Helm Deployment Logs

```bash
# Find the deployment script name
az resource list \
  --resource-group <rg-name> \
  --resource-type Microsoft.Resources/deploymentScripts \
  --query "[].name" -o tsv

# View logs
az deployment-scripts show-log \
  --resource-group <rg-name> \
  --name helm-install-<uniquestring>
```

### Check Neo4j Pods

```bash
# Get AKS credentials
az aks get-credentials \
  --name <cluster-name> \
  --resource-group <rg-name> \
  --overwrite-existing

# Check pods
kubectl get pods -n neo4j

# View pod details
kubectl describe pod neo4j-0 -n neo4j

# View logs
kubectl logs neo4j-0 -n neo4j
kubectl logs neo4j-0 -n neo4j --previous  # If pod restarted
```

---

## Common Issues and Solutions

### Issue 1: Helm Deployment Times Out

**Symptom**: Deployment script shows "Error: context deadline exceeded"

**Cause**: Helm chart parameters are incorrect, causing StatefulSet to fail

**Check**:
```bash
# View the actual error
kubectl describe statefulset neo4j -n neo4j
kubectl get events -n neo4j --sort-by='.lastTimestamp'
```

**Common Root Causes**:
1. **Storage parameter wrong**: Check line 260 in helm-deployment.bicep uses `requests.storage`
2. **Resource parameter wrong**: Check lines 264-265 use `neo4j.resources.*`
3. **Memory configuration invalid**: Check lines 269-271 use escaped dots

**Solution**: Verify helm-deployment.bicep matches HELM_PARAMETERS.md

---

### Issue 2: Pod Shows "ImagePullBackOff"

**Symptom**: Pod stuck in ImagePullBackOff or ErrImagePull state

**Check**:
```bash
kubectl describe pod neo4j-0 -n neo4j | grep -A 5 "Events:"
```

**Common Causes**:
1. **Wrong image tag format**: Helm chart expects automatic selection, not explicit override
2. **Network connectivity**: AKS can't reach Docker Hub or Neo4j registry

**Solution**:
- Verify helm-deployment.bicep does NOT set `image.repository` or `image.tag` explicitly
- Let chart automatically select image based on `neo4j.edition` and `neo4j.minimumClusterSize`
- Check AKS network connectivity: `kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup hub.docker.com`

---

### Issue 3: Pod Shows "CrashLoopBackOff"

**Symptom**: Pod starts but crashes repeatedly

**Check**:
```bash
kubectl logs neo4j-0 -n neo4j
kubectl logs neo4j-0 -n neo4j --previous
```

**Common Causes**:
1. **Invalid Neo4j configuration**: JVM memory settings exceed pod limits
2. **Invalid license agreement**: acceptLicenseAgreement value wrong
3. **Insufficient resources**: Resource requests too high for nodes

**Solutions**:
- **Memory issue**: Check heap size (4G) + page cache (3G) < total memory (8Gi) with some overhead
- **License issue**: Verify `licenseAgreement` variable is "eval" or "yes" (line 72 helm-deployment.bicep)
- **Resources**: Check node pool has capacity for requested resources

---

### Issue 4: PVC Not Bound

**Symptom**: PersistentVolumeClaim shows "Pending" state

**Check**:
```bash
kubectl get pvc -n neo4j
kubectl describe pvc data-neo4j-0 -n neo4j
```

**Common Causes**:
1. **StorageClass doesn't exist**: storage.bicep deployment failed
2. **Wrong storage class name**: Mismatch between modules
3. **No available disk space**: Azure subscription quota exceeded

**Solutions**:
- Verify StorageClass exists: `kubectl get storageclass neo4j-premium`
- Check storage.bicep deployed successfully
- Verify storageClassName matches between storage.bicep (line 19) and helm-deployment.bicep (line 81)
- Check Azure disk quota: `az vm list-usage --location westeurope --query "[?localName=='Total Regional vCPUs']"`

---

### Issue 5: LoadBalancer Service No External IP

**Symptom**: Service stuck in "pending" state for external IP

**Check**:
```bash
kubectl get service neo4j -n neo4j
kubectl describe service neo4j -n neo4j
```

**Common Causes**:
1. **Azure Load Balancer quota exceeded**
2. **Subnet has no available IPs**
3. **NSG blocking traffic**
4. **Service not configured as LoadBalancer type**

**Solutions**:
- Verify service type: `kubectl get service neo4j -n neo4j -o jsonpath='{.spec.type}'` should be "LoadBalancer"
- Check helm-deployment.bicep line 281 sets `services.neo4j.spec.type=LoadBalancer`
- Check network.bicep provides sufficient address space
- Wait 5-10 minutes - Azure LoadBalancer provisioning can be slow

---

### Issue 6: Cannot Connect to Neo4j

**Symptom**: Have external IP but connection refused

**Check**:
```bash
# Verify pod is ready
kubectl get pods -n neo4j

# Check Neo4j is listening
kubectl exec neo4j-0 -n neo4j -- netstat -tulpn | grep 7474
kubectl exec neo4j-0 -n neo4j -- netstat -tulpn | grep 7687

# Test from inside cluster
kubectl run -it --rm debug --image=busybox --restart=Never -- nc -zv neo4j.neo4j.svc.cluster.local 7687
```

**Common Causes**:
1. **Pod not ready**: Neo4j still initializing (can take 2-3 minutes)
2. **Password wrong**: Mismatch between deployment and connection attempt
3. **Firewall blocking**: Local firewall blocking ports 7474 or 7687

**Solutions**:
- Wait for pod to be "1/1 Ready": `kubectl get pods -n neo4j -w`
- Verify password matches deployment: Check saved connection info in `.arm-testing/results/`
- Test with curl: `curl http://<external-ip>:7474/browser/`
- Try port-forward for testing: `kubectl port-forward neo4j-0 7474:7474 7687:7687 -n neo4j`

---

## Verification Checklist

After deployment completes, verify:

### Infrastructure Layer
- [ ] Resource group created
- [ ] VNet and subnets exist
- [ ] Managed identity created
- [ ] AKS cluster running
- [ ] Node pools have correct number of nodes
- [ ] StorageClass "neo4j-premium" exists

```bash
az group show --name <rg-name>
az network vnet list --resource-group <rg-name>
az identity list --resource-group <rg-name>
az aks show --name <cluster-name> --resource-group <rg-name>
kubectl get storageclass
```

### Application Layer
- [ ] Namespace "neo4j" exists
- [ ] StatefulSet "neo4j" exists with correct replica count
- [ ] All pods are "Running" and "1/1 Ready"
- [ ] All PVCs are "Bound"
- [ ] Service "neo4j" has external IP

```bash
kubectl get namespace neo4j
kubectl get statefulset -n neo4j
kubectl get pods -n neo4j
kubectl get pvc -n neo4j
kubectl get service -n neo4j
```

### Neo4j Connectivity
- [ ] Neo4j Browser accessible at http://<ip>:7474
- [ ] Can login with neo4j and provided password
- [ ] Can run simple query: `RETURN 1 AS result`
- [ ] License type shows correctly

```bash
# Via Browser UI or
kubectl exec neo4j-0 -n neo4j -- cypher-shell -u neo4j -p <password> "RETURN 1 AS result"
```

---

## Debugging Commands Reference

### Helm Operations
```bash
# List releases
helm list -n neo4j

# Get release status
helm status neo4j -n neo4j

# Get values used
helm get values neo4j -n neo4j

# Get generated manifests
helm get manifest neo4j -n neo4j

# Uninstall release (for testing)
helm uninstall neo4j -n neo4j
```

### Kubernetes Debugging
```bash
# Get all resources in namespace
kubectl get all -n neo4j

# View events (recent activity)
kubectl get events -n neo4j --sort-by='.lastTimestamp'

# View resource usage
kubectl top pods -n neo4j
kubectl top nodes

# Describe resources
kubectl describe statefulset neo4j -n neo4j
kubectl describe pod neo4j-0 -n neo4j
kubectl describe pvc data-neo4j-0 -n neo4j
kubectl describe service neo4j -n neo4j

# Execute commands in pod
kubectl exec -it neo4j-0 -n neo4j -- bash
kubectl exec neo4j-0 -n neo4j -- cat /var/log/neo4j/neo4j.log
kubectl exec neo4j-0 -n neo4j -- ps aux | grep neo4j
```

### Azure Debugging
```bash
# View deployment operations
az deployment group list --resource-group <rg-name>

# View failed operations
az deployment operation group list \
  --resource-group <rg-name> \
  --name main \
  --query "[?properties.provisioningState=='Failed']"

# View activity log
az monitor activity-log list \
  --resource-group <rg-name> \
  --max-events 20

# View AKS diagnostics
az aks show --name <cluster-name> --resource-group <rg-name>
az aks get-upgrades --name <cluster-name> --resource-group <rg-name>
```

---

## Getting Help

### Collect Diagnostics

Before asking for help, collect this information:

```bash
# 1. Deployment status
az deployment group show --resource-group <rg-name> --name main > deployment-status.json

# 2. Helm deployment logs
az deployment-scripts show-log \
  --resource-group <rg-name> \
  --name helm-install-<uniquestring> > helm-logs.txt

# 3. Kubernetes state
kubectl get all -n neo4j -o yaml > k8s-all.yaml
kubectl get events -n neo4j > k8s-events.txt
kubectl describe pod neo4j-0 -n neo4j > pod-describe.txt
kubectl logs neo4j-0 -n neo4j > neo4j-logs.txt

# 4. StorageClass
kubectl get storageclass -o yaml > storageclasses.yaml
```

### Contact Support

Provide:
1. Deployment logs (from above)
2. Exact error messages
3. Template version (check CLEAN_HELM.md status)
4. Azure subscription type (Free trial, Pay-as-you-go, Enterprise)
5. Azure region used
6. Parameters used (remove sensitive data like passwords)

---

## Quick Recovery Steps

### Start Fresh

If deployment is completely broken:

```bash
# 1. Delete the resource group
cd marketplace/neo4j-enterprise-aks
./delete.sh <rg-name>

# Wait for deletion to complete (can take 5-10 minutes)
az group show --name <rg-name>  # Should return error

# 2. Clean up validation system state
cd ../../deployments
uv run neo4j-deploy cleanup --all --force

# 3. Deploy fresh
uv run neo4j-deploy deploy --scenario aks-standalone-v5
```

### Manual Cleanup

If automatic cleanup fails:

```bash
# Delete Helm release first
az aks get-credentials --name <cluster-name> --resource-group <rg-name>
helm uninstall neo4j -n neo4j

# Delete deployment scripts (can block RG deletion)
az resource list \
  --resource-group <rg-name> \
  --resource-type Microsoft.Resources/deploymentScripts \
  --query "[].id" -o tsv | \
  xargs -I {} az resource delete --ids {}

# Force delete resource group
az group delete --name <rg-name> --yes --no-wait
```

---

## Performance Optimization

### If Deployment is Slow

Normal timing:
- Infrastructure deployment: 5-8 minutes
- Helm chart installation: 3-5 minutes
- Neo4j initialization: 2-3 minutes
- **Total**: 10-16 minutes

If significantly slower:
1. Check Azure region load: Try different region
2. Check node pool VM size: Ensure adequate resources
3. Check AKS API responsiveness: `az aks show` should be fast

### If Neo4j is Slow

After deployment succeeds but queries are slow:

```bash
# Check resource usage
kubectl top pods -n neo4j

# Check if memory is constrained
kubectl logs neo4j-0 -n neo4j | grep -i "memory"

# Review Neo4j configuration
kubectl exec neo4j-0 -n neo4j -- cat /var/lib/neo4j/conf/neo4j.conf
```

Consider increasing:
- `memoryRequest` parameter (currently 8Gi)
- `cpuRequest` parameter (currently 2000m)
- `diskSize` parameter (currently 32GB)

---

**Need more help?** Check:
- HELM_PARAMETERS.md - Complete parameter reference
- CLEAN_HELM.md - Implementation progress and known issues
- Official docs: https://neo4j.com/docs/operations-manual/current/kubernetes/
