# Troubleshooting Neo4j on AKS

## Initial Setup - Authenticate kubectl

First, configure kubectl to connect to your AKS cluster:

```bash
# Get AKS credentials (configures kubectl automatically)
az aks get-credentials \
  --resource-group <your-resource-group> \
  --name <your-aks-cluster-name> \
  --overwrite-existing
```

Verify connection:
```bash
kubectl cluster-info
kubectl get nodes
```

## Check Deployment Status

### View AKS Cluster
```bash
# Cluster status
az aks show \
  --resource-group <resource-group> \
  --name <cluster-name> \
  --query "{status: provisioningState, k8sVersion: kubernetesVersion}" \
  --output table

# Node status
az aks show \
  --resource-group <resource-group> \
  --name <cluster-name> \
  --query "agentPoolProfiles[].{name:name, count:count, vmSize:vmSize}" \
  --output table
```

### View Neo4j Pods
```bash
# Pod status
kubectl get pods -n neo4j

# Detailed pod info
kubectl describe pod <pod-name> -n neo4j

# Watch pods in real-time
kubectl get pods -n neo4j -w
```

### Check Pod Logs
```bash
# View pod logs
kubectl logs <pod-name> -n neo4j

# Follow logs in real-time
kubectl logs <pod-name> -n neo4j -f

# View previous container logs (if restarted)
kubectl logs <pod-name> -n neo4j --previous
```

### Check Services and LoadBalancer
```bash
# View services
kubectl get services -n neo4j

# Check LoadBalancer external IP
kubectl get service -n neo4j -o wide

# Service details
kubectl describe service <service-name> -n neo4j
```

### Check StatefulSets
```bash
# View StatefulSets
kubectl get statefulsets -n neo4j

# StatefulSet details
kubectl describe statefulset <statefulset-name> -n neo4j
```

## Common Issues

### Pods Not Ready
```bash
# Check pod events
kubectl describe pod <pod-name> -n neo4j | grep -A 20 Events

# Check startup/readiness probe failures
kubectl describe pod <pod-name> -n neo4j | grep -A 5 "Startup\|Readiness"

# Check if service account token is mounted
kubectl get pod <pod-name> -n neo4j -o jsonpath='{.spec.automountServiceAccountToken}'
```

### RBAC Permissions Issues
```bash
# List service accounts
kubectl get serviceaccount -n neo4j

# Check role bindings
kubectl get rolebinding -n neo4j

# Test service account permissions
kubectl auth can-i list services \
  --as=system:serviceaccount:neo4j:<service-account-name> \
  -n neo4j
```

### Network/Connectivity Issues
```bash
# Check endpoints
kubectl get endpoints -n neo4j

# Test connectivity from inside a pod
kubectl exec -it <pod-name> -n neo4j -- bash

# Inside pod: test Neo4j ports
nc -zv localhost 7687  # Bolt
nc -zv localhost 7474  # HTTP
nc -zv localhost 6000  # Cluster discovery
```

### View Helm Deployment Logs (if deployment failed)
```bash
# List deployment scripts
az deployment-scripts list \
  --resource-group <resource-group> \
  --query "[].name" \
  --output table

# View deployment script logs
az deployment-scripts show-log \
  --resource-group <resource-group> \
  --name <script-name>
```

## Access Neo4j

### Via LoadBalancer
```bash
# Get external IP
EXTERNAL_IP=$(kubectl get service -n neo4j -o jsonpath='{.items[?(@.spec.type=="LoadBalancer")].status.loadBalancer.ingress[0].ip}')

echo "Browser: http://$EXTERNAL_IP:7474"
echo "Bolt: neo4j://$EXTERNAL_IP:7687"
```

### Port Forward (for testing)
```bash
# Forward ports to localhost
kubectl port-forward -n neo4j <pod-name> 7474:7474 7687:7687

# Access at: http://localhost:7474
```

## Cluster-Specific Troubleshooting

### Check Cluster Formation
```bash
# View all cluster pods
kubectl get pods -n neo4j -l app=neo4j-cluster

# Check cluster discovery configuration
kubectl get configmap -n neo4j -o yaml | grep -A 10 "dbms.cluster\|dbms.kubernetes"

# Check cluster services with correct labels
kubectl get services -n neo4j -l helm.neo4j.com/clustering=true
```

### Restart Pods
```bash
# Delete pod (StatefulSet will recreate it)
kubectl delete pod <pod-name> -n neo4j

# Restart all cluster pods
kubectl delete pod -l app=neo4j-cluster -n neo4j
```

## Cleanup

### Delete Neo4j Resources
```bash
# Delete all resources in namespace
kubectl delete namespace neo4j
```

### Delete Entire Resource Group
```bash
# Delete resource group (removes everything)
az group delete --name <resource-group> --yes --no-wait
```

## Getting Help

If issues persist, collect diagnostic information:

```bash
# Gather diagnostic info
kubectl describe pod <pod-name> -n neo4j > pod-describe.txt
kubectl logs <pod-name> -n neo4j > pod-logs.txt
kubectl get events -n neo4j --sort-by='.lastTimestamp' > events.txt
kubectl get all -n neo4j -o yaml > all-resources.yaml
```

Common issues and solutions are documented in:
- `CLUSTER_AKS_WORKLOAD_IDENTITY_FIX.md` - Service account token mounting issue
- `CLUSTER_BEST_PRACTICES.md` - Multi-server deployment architecture
- Azure support: https://aka.ms/akshelp
- Neo4j support: https://neo4j.com/support/
