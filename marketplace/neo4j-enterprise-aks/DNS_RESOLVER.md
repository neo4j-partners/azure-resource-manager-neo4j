# DNS Resolver Implementation for Neo4j Cluster Discovery

## Overview

This document describes the switch from K8S resolver to DNS resolver for Neo4j cluster discovery in the AKS deployment, the changes made, and the current issues being faced.

## Background

Neo4j supports two primary discovery mechanisms for Kubernetes clusters:

| Resolver Type | How It Works | Requirements |
|---------------|--------------|--------------|
| **K8S** (default) | Queries Kubernetes API to list services by label selector | RBAC, ServiceAccount, token mounting |
| **DNS** | Uses DNS A records from a headless service | Headless service with `clusterIP: None` |

### Why Switch to DNS Resolver?

1. **Simpler configuration** - No RBAC/ServiceAccount requirements
2. **AKS Workload Identity compatibility** - K8S resolver conflicts with workload identity's token handling
3. **Standard Kubernetes pattern** - DNS-based service discovery is a fundamental K8S concept

---

## Neo4j 5.x Port Configuration

Based on [Neo4j Operations Manual](https://neo4j.com/docs/operations-manual/current/configuration/ports/):

| Port | Purpose | Neo4j 5.x | Neo4j 2025+ |
|------|---------|-----------|-------------|
| **5000** | Discovery (V1) | ✓ Used | ❌ Removed |
| **6000** | Internal cluster/Discovery (V2) | ✓ Used | ✓ Primary |
| **7000** | Raft consensus | ✓ Used | ✓ Used |
| **7688** | Transaction routing | ✓ Used | ✓ Used |

**Important:** Neo4j 5.x uses port 5000 for V1 discovery. Starting with Neo4j 2025.01, port 5000 is removed and only port 6000 is used.

---

## Changes Made

### 1. Namespace Creation Script (Pre-deployment)

Added creation of **two headless services** before Neo4j pods start:

#### Official Neo4j Headless Service Chart
```bash
helm upgrade --install neo4j-cluster-headless neo4j/neo4j-headless-service \
  --namespace neo4j \
  --set neo4j.name=neo4j-cluster
```

#### Custom Discovery Headless Service
```yaml
apiVersion: v1
kind: Service
metadata:
  name: neo4j-cluster-discovery
  namespace: neo4j
  labels:
    app: neo4j-cluster
    helm.neo4j.com/clustering: "true"
    helm.neo4j.com/service: "discovery"
spec:
  type: ClusterIP
  clusterIP: None                    # Headless - returns pod IPs directly
  publishNotReadyAddresses: true     # Include pods before they're ready
  selector:
    app: neo4j-cluster
    helm.neo4j.com/clustering: "true"
  ports:
    - name: tcp-discovery-v1
      port: 5000                     # V1 discovery (Neo4j 5.x)
      targetPort: 5000
    - name: tcp-discovery-v2
      port: 6000                     # V2 discovery
      targetPort: 6000
    - name: tcp-raft
      port: 7000
      targetPort: 7000
    - name: tcp-tx
      port: 7688
      targetPort: 7688
```

**Key points:**
- `clusterIP: None` makes it headless (DNS returns pod IPs, not a virtual IP)
- `publishNotReadyAddresses: true` ensures pods are discoverable before becoming ready
- Exposes both V1 (5000) and V2 (6000) discovery ports for compatibility

### 2. Helm Values Configuration

Removed K8S resolver settings:
```bash
# REMOVED:
# --set serviceAccount.create=true
# --set rbac.create=true
# --set podSpec.automountServiceAccountToken=true
```

Added DNS resolver configuration via values file:
```yaml
config:
  dbms.cluster.discovery.resolver_type: "DNS"
  # V1 discovery (Neo4j 5.x default with V1_ONLY)
  dbms.cluster.discovery.endpoints: "neo4j-cluster-discovery.neo4j.svc.cluster.local:5000"
  # V2 discovery (for compatibility)
  dbms.cluster.discovery.v2.endpoints: "neo4j-cluster-discovery.neo4j.svc.cluster.local:6000"
```

### 3. File Changes

**Modified:** `modules/helm-deployment.bicep`
- Lines 160-228: Added headless service chart installation and discovery service creation
- Lines 452-498: Added DNS resolver config with both V1 and V2 endpoints
- Lines 560-630: Updated verification to check discovery service and both ports

---

## How DNS Discovery Works

```
                                    ┌─────────────────────────────┐
                                    │   neo4j-cluster-discovery   │
                                    │   (Headless Service)        │
                                    │   clusterIP: None           │
                                    └─────────────────────────────┘
                                                 │
                                    DNS A Record Query Returns:
                                    ┌────────────┼────────────┐
                                    │            │            │
                                    ▼            ▼            ▼
                              10.1.0.20    10.1.0.34    10.1.0.xx
                              (server-1)  (server-2)   (server-3)
                                    │            │            │
                                    └────────────┼────────────┘
                                                 │
                              Neo4j 5.x: Connect on port 5000 (V1)
                              Neo4j 2025+: Connect on port 6000 (V2)
```

**Discovery flow:**
1. Neo4j pod starts and reads `dbms.cluster.discovery.endpoints`
2. Performs DNS lookup: `neo4j-cluster-discovery.neo4j.svc.cluster.local`
3. DNS returns A records for all pods matching the service selector
4. Neo4j connects to each IP on discovery port (5000 for V1, 6000 for V2)
5. Raft consensus forms when `minimumClusterSize` members join

---

## Latest Deployment Status (November 25, 2025)

### What's Working

**Services created correctly:**
```
NAME                      TYPE           CLUSTER-IP       EXTERNAL-IP     PORTS
neo4j-cluster-discovery   ClusterIP      None             <none>          5000,6000,7000,7688
neo4j-cluster-headless    ClusterIP      None             <none>          7474,7473,7687
neo4j-cluster-lb-neo4j    LoadBalancer   172.16.211.143   4.175.188.141   7474,7473,7687
server-1-internals        ClusterIP      172.16.91.2      <none>          6362,7687,7474,7688,5000,7000,6000
server-2-internals        ClusterIP      172.16.157.214   <none>          6362,7687,7474,7688,5000,7000,6000
```

**Discovery endpoints populated:**
```yaml
# kubectl get endpoints neo4j-cluster-discovery -n neo4j
subsets:
- addresses:
  - ip: 10.1.0.20  # server-1-0
  - ip: 10.1.0.34  # server-2-0
  ports:
  - name: tcp-discovery-v1
    port: 5000
  - name: tcp-discovery-v2
    port: 6000
  - name: tcp-raft
    port: 7000
  - name: tcp-tx
    port: 7688
```

**User config applied correctly:**
```yaml
# kubectl get configmap server-1-user-config -n neo4j
dbms.cluster.discovery.resolver_type: DNS
dbms.cluster.discovery.endpoints: neo4j-cluster-discovery.neo4j.svc.cluster.local:5000
dbms.cluster.discovery.v2.endpoints: neo4j-cluster-discovery.neo4j.svc.cluster.local:6000
```

### Current Issues

#### Issue 1: Configuration Conflict (Persists)

The Helm chart creates TWO ConfigMaps that are merged:

| ConfigMap | Resolver Setting | Source |
|-----------|------------------|--------|
| `server-1-default-config` | `dbms.cluster.discovery.resolver_type: K8S` | Helm chart default |
| `server-1-user-config` | `dbms.cluster.discovery.resolver_type: DNS` | Our override |

The `default-config` still sets K8S-specific settings:
```yaml
dbms.cluster.discovery.resolver_type: K8S
dbms.cluster.discovery.version: V1_ONLY
dbms.kubernetes.service_port_name: tcp-discovery
dbms.kubernetes.label_selector: app=neo4j-cluster,helm.neo4j.com/service=internals,...
dbms.kubernetes.discovery.v2.service_port_name: tcp-tx
```

**Question:** Does `user-config` actually override `default-config`? The Neo4j startup script should merge configs with user-config taking precedence, but this hasn't been verified.

#### Issue 2: Cluster Not Forming (Persists)

Despite correct DNS configuration:
- Pods stay at `0/1 Running` (not ready)
- Startup probes fail: `dial tcp 10.1.0.20:7687: connect: connection refused`
- Neo4j not accepting Bolt connections after several minutes

#### Issue 3: AKS Kubelet Connectivity (Persists)

Cannot view pod logs due to konnectivity-agent issues:
```
Error from server: proxy error from localhost:9443 while dialing 10.1.0.4:10250, code 504
```

This prevents debugging the actual Neo4j startup process.

---

## Configuration Reference

### Current user-config (DNS Resolver)
```yaml
# In server-N-user-config ConfigMap
dbms.cluster.discovery.resolver_type: DNS
dbms.cluster.discovery.endpoints: neo4j-cluster-discovery.neo4j.svc.cluster.local:5000
dbms.cluster.discovery.v2.endpoints: neo4j-cluster-discovery.neo4j.svc.cluster.local:6000
server.memory.heap.initial_size: "3500M"
server.memory.heap.max_size: "3500M"
server.memory.pagecache.size: "3G"
```

### Conflicting default-config (K8S Resolver)
```yaml
# In server-N-default-config ConfigMap (from Helm chart)
dbms.cluster.discovery.resolver_type: K8S
dbms.cluster.discovery.version: V1_ONLY
dbms.kubernetes.label_selector: app=neo4j-cluster,helm.neo4j.com/service=internals,helm.neo4j.com/clustering=true
dbms.kubernetes.service_port_name: tcp-discovery
dbms.kubernetes.discovery.v2.service_port_name: tcp-tx
server.discovery.advertised_address: $(bash -c 'echo ${SERVICE_NEO4J_INTERNALS}')
```

---

## Things Tried

### Attempt 1: Basic DNS Resolver
- Created manual `neo4j-cluster-internals` headless service
- Set `dbms.cluster.discovery.resolver_type: DNS`
- Set `dbms.cluster.discovery.endpoints` to port 6000
- **Result:** DNS resolution worked but cluster didn't form

### Attempt 2: Neo4j Headless Service Helm Chart
- Installed official `neo4j/neo4j-headless-service` chart
- Created separate `neo4j-cluster-discovery` service
- **Result:** Services created correctly, still investigating

### Attempt 3: Dual V1/V2 Discovery Ports
- Added both port 5000 (V1) and port 6000 (V2) to discovery service
- Configured both `dbms.cluster.discovery.endpoints` (V1) and `dbms.cluster.discovery.v2.endpoints` (V2)
- **Result:** Configuration applied correctly, cluster still not forming

### Port Verification
- Confirmed Neo4j 5.x uses port 5000 for V1 discovery
- Confirmed Neo4j 2025+ will use port 6000 only
- Updated verification scripts to check both ports

---

## Next Steps

1. **Resolve kubelet connectivity** - Fix AKS konnectivity-agent issue to enable log access
2. **Verify config merge order** - Confirm `user-config` overrides `default-config`
3. **Try explicit K8S setting overrides** - Set empty/null values for `dbms.kubernetes.*` settings in user-config
4. **Enable debug logging** - Deploy with `enableDebugMode=Yes` to get verbose startup logs
5. **Consider reverting to K8S resolver** - If DNS continues to fail, K8S resolver with proper RBAC may be more reliable

---

## Related Documentation

- [Neo4j Cluster Discovery](https://neo4j.com/docs/operations-manual/current/clustering/setup/discovery/)
- [Neo4j Ports Configuration](https://neo4j.com/docs/operations-manual/current/configuration/ports/)
- [Neo4j Changes in 2025.x](https://neo4j.com/docs/operations-manual/current/changes-deprecations-removals/)
- [Neo4j Kubernetes Configuration](https://neo4j.com/docs/operations-manual/current/kubernetes/configuration/)
- [Neo4j Helm Charts](https://github.com/neo4j/helm-charts)
- [CLUSTER_BEST_PRACTICES.md](./CLUSTER_BEST_PRACTICES.md) - Multi-installation approach documentation

---

**Last Updated:** November 25, 2025
**Status:** DNS resolver configured with V1/V2 ports, services working, cluster not forming - kubelet connectivity blocking debug
