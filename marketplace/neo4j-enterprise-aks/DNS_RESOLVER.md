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

## Changes Made

### 1. Namespace Creation Script (Pre-deployment)

Added creation of a **shared headless service** before Neo4j pods start:

```yaml
# Created in namespace creation step
apiVersion: v1
kind: Service
metadata:
  name: neo4j-cluster-internals
  namespace: neo4j
  labels:
    app: neo4j-cluster
    helm.neo4j.com/clustering: "true"
    helm.neo4j.com/service: "internals"
spec:
  type: ClusterIP
  clusterIP: None                    # Headless - returns pod IPs directly
  publishNotReadyAddresses: true     # Include pods before they're ready
  selector:
    app: neo4j-cluster
    helm.neo4j.com/clustering: "true"
  ports:
    - name: tcp-discovery
      port: 6000
    - name: tcp-raft
      port: 7000
    - name: tcp-tx
      port: 7688
    - name: tcp-bolt
      port: 7687
    - name: tcp-http
      port: 7474
```

**Key points:**
- `clusterIP: None` makes it headless (DNS returns pod IPs, not a virtual IP)
- `publishNotReadyAddresses: true` ensures pods are discoverable before becoming ready
- Selector matches all Neo4j cluster pods

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
  dbms.cluster.discovery.endpoints: "neo4j-cluster-internals.neo4j.svc.cluster.local:6000"
```

### 3. File Changes

**Modified:** `modules/helm-deployment.bicep`
- Lines 102-225: Added headless service creation in namespace setup
- Lines 391-414: Removed K8S RBAC settings, added DNS resolver config
- Lines 435-496: Added DNS endpoint configuration to values file

---

## How DNS Discovery Works

```
                                    ┌─────────────────────────────┐
                                    │   neo4j-cluster-internals   │
                                    │   (Headless Service)        │
                                    │   clusterIP: None           │
                                    └─────────────────────────────┘
                                                 │
                                    DNS A Record Query Returns:
                                    ┌────────────┼────────────┐
                                    │            │            │
                                    ▼            ▼            ▼
                              10.1.0.34    10.1.0.78    10.1.0.18
                              (server-1)  (server-2)   (server-3)
                                    │            │            │
                                    └────────────┼────────────┘
                                                 │
                              All pods connect on port 6000
                              to form Raft consensus cluster
```

**Discovery flow:**
1. Neo4j pod starts and reads `dbms.cluster.discovery.endpoints`
2. Performs DNS lookup: `neo4j-cluster-internals.neo4j.svc.cluster.local`
3. DNS returns A records for all pods matching the service selector
4. Neo4j connects to each IP on port 6000 (discovery port)
5. Raft consensus forms when `minimumClusterSize` members join

---

## Verified Working

From deployment logs, DNS resolution IS working:

```
INFO  Resolved endpoints with DNS{endpoints:'[neo4j-cluster-internals.neo4j.svc.cluster.local:6000]'}
      to '[10.1.0.14:6000, 10.1.0.53:6000, 10.1.0.89:6000]'
```

**What works:**
- Headless service created successfully (`clusterIP=None`)
- All 3 pod IPs appear in service endpoints
- DNS resolution returns all 3 IPs
- Neo4j logs show successful DNS resolution

---

## Current Issues

### Issue 1: Configuration Conflict

The Helm chart creates TWO ConfigMaps that are merged:

| ConfigMap | Resolver Setting | Source |
|-----------|------------------|--------|
| `server-1-default-config` | `dbms.cluster.discovery.resolver_type: K8S` | Helm chart default |
| `server-1-user-config` | `dbms.cluster.discovery.resolver_type: DNS` | Our override |

The `default-config` also sets K8S-specific settings:
```yaml
dbms.cluster.discovery.version: V1_ONLY
dbms.kubernetes.service_port_name: tcp-discovery
dbms.kubernetes.label_selector: app=neo4j-cluster,helm.neo4j.com/service=internals,...
dbms.kubernetes.discovery.v2.service_port_name: tcp-tx
```

**Hypothesis:** These K8S-specific settings may interfere with DNS resolver even when `resolver_type` is overridden to DNS.

### Issue 2: Cluster Not Forming

Despite DNS resolution working, the cluster doesn't form:
- All 3 pods stay at `0/1 Running` (not ready)
- Startup probes fail: `dial tcp <ip>:7687: connect: connection refused`
- Pods have been running 40+ minutes without becoming ready

### Issue 3: AKS Kubelet Connectivity

Persistent `504 Gateway Timeout` errors when accessing pod logs:
```
Error from server: proxy error from localhost:9443 while dialing 10.1.0.33:10250, code 504
```

This is an AKS konnectivity-agent issue that prevents debugging via `kubectl logs`.

---

## Potential Solutions

### Option A: Disable K8S Resolver Settings in Default Config

Override ALL K8S-related discovery settings in user-config:
```yaml
config:
  dbms.cluster.discovery.resolver_type: "DNS"
  dbms.cluster.discovery.endpoints: "neo4j-cluster-internals.neo4j.svc.cluster.local:6000"
  # Explicitly disable K8S resolver settings
  dbms.kubernetes.label_selector: ""
  dbms.kubernetes.service_port_name: ""
```

### Option B: Revert to K8S Resolver with Proper RBAC

If DNS resolver continues to have issues, revert to K8S resolver with:
- Explicit ServiceAccount creation
- RBAC role with `list services` permission
- `automountServiceAccountToken=true` to override AKS Workload Identity

### Option C: Use Neo4j Cluster Headless Service Helm Chart

Neo4j provides a separate Helm chart `neo4j-cluster-headless-service` specifically for DNS-based discovery that may handle the configuration properly.

---

## Configuration Reference

### Current user-config (DNS Resolver)
```yaml
# In server-N-user-config ConfigMap
dbms.cluster.discovery.endpoints: neo4j-cluster-internals.neo4j.svc.cluster.local:6000
dbms.cluster.discovery.resolver_type: DNS
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
```

---

## Next Steps

1. **Investigate config merge order** - Verify `user-config` actually overrides `default-config`
2. **Try explicit K8S setting overrides** - Set empty values for `dbms.kubernetes.*` settings
3. **Check Neo4j debug logs** - Once kubelet connectivity is resolved, examine full startup logs
4. **Consider reverting to K8S resolver** - If DNS continues to fail, K8S resolver with proper RBAC may be more reliable

---

## Related Documentation

- [Neo4j Cluster Discovery](https://neo4j.com/docs/operations-manual/current/clustering/setup/discovery/)
- [Neo4j Kubernetes Configuration](https://neo4j.com/docs/operations-manual/current/kubernetes/configuration/)
- [Neo4j Helm Charts](https://github.com/neo4j/helm-charts)
- [CLUSTER_BEST_PRACTICES.md](./CLUSTER_BEST_PRACTICES.md) - Multi-installation approach documentation

---

**Last Updated:** November 25, 2025
**Status:** DNS resolver configured but cluster not forming - investigation ongoing
