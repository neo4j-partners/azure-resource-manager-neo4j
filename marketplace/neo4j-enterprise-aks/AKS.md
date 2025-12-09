# Neo4j AKS Cluster Formation Issue

## Summary

We are deploying a 3-node Neo4j Enterprise cluster on Azure Kubernetes Service (AKS) using the official Neo4j Helm chart (version 5.26.16) following the multi-installation pattern described in the official documentation. Our infrastructure appears correctly configured, but the cluster fails to form after multiple hours of runtime.

## Our Understanding & Configuration

Based on the [Neo4j Kubernetes Operations Manual](https://neo4j.com/docs/operations-manual/current/kubernetes/quickstart-cluster/), we understand that:

> "A cluster with three servers requires installing the neo4j chart three times."

We are following this pattern by deploying three separate Helm releases (`server-1`, `server-2`, `server-3`), each creating one StatefulSet with one pod. All three releases share the same `neo4j.name=neo4j-cluster` parameter to enable cluster discovery.

### Helm Parameters (Applied to All Three Installations)

- `neo4j.name`: "neo4j-cluster" (identical across all servers)
- `neo4j.minimumClusterSize`: 3
- `neo4j.edition`: "enterprise"
- `neo4j.acceptLicenseAgreement`: "eval"
- `neo4j.password`: (set via `--set-file`)
- RBAC enabled: `serviceAccount.create=true`, `rbac.create=true`
- Service account token mounting enabled: `podSpec.automountServiceAccountToken=true`
- Pod anti-affinity enabled: `podSpec.podAntiAffinity=true`

### Kubernetes Resources Created

**Pods (All Running, None Ready):**
- `server-1-0` on node vmss000001 (IP: 10.1.0.82)
- `server-2-0` on node vmss000000 (IP: 10.1.0.39)
- `server-3-0` on node vmss000002 (IP: 10.1.0.12)

**Services per Server:**
- `server-X`: ClusterIP for Bolt/HTTP access
- `server-X-admin`: ClusterIP for admin access
- `server-X-internals`: ClusterIP for cluster communication (ports 6000, 6362, 7000, 7474, 7687, 7688)

**Shared LoadBalancer:**
- `neo4j-cluster-lb-neo4j`: Azure LoadBalancer with external IP (currently no endpoints due to pods not ready)

**RBAC (Per Server):**
- ServiceAccount: `server-X`
- Role: `server-X-service-reader` with permissions to get/watch/list services and endpoints
- RoleBinding: `server-X-service-binding`

**Pod Labels (Verified Identical Across All Pods):**
- `app=neo4j-cluster`
- `helm.neo4j.com/clustering=true`
- `helm.neo4j.com/neo4j.name=neo4j-cluster`

### Configuration Settings (From ConfigMap)

The K8S resolver is configured with:
- `dbms.cluster.discovery.resolver_type`: K8S
- `dbms.kubernetes.label_selector`: "app=neo4j-cluster,helm.neo4j.com/service=internals,helm.neo4j.com/clustering=true"
- `dbms.cluster.minimum_initial_system_primaries_count`: 3

Advertised addresses use environment variables via bash scripts:
- `server.cluster.advertised_address`: Uses `SERVICE_NEO4J_INTERNALS` (e.g., "server-1-internals.neo4j.svc.cluster.local")
- `server.bolt.advertised_address`: Uses `SERVICE_NEO4J` (e.g., "server-1.neo4j.svc.cluster.local")

## Problem Description

After deploying all three servers and waiting over 2 hours, the cluster fails to form. Specifically:

**Symptoms:**
1. All three pods remain in `Running` state but never reach `Ready` (0/1)
2. Startup probes fail continuously with "connection refused" on port 7687
3. Each pod has restarted at least once
4. Over 1300+ startup probe failures recorded per pod

**What We See in Neo4j Logs (via Azure Container Insights):**

Neo4j appears to start successfully:
- License is accepted (Evaluation mode)
- K8S service discovery resolver initializes
- Discovery successfully finds and resolves endpoints for all three servers
- External scripts execute to retrieve advertised addresses

However, Neo4j enters a continuous loop:
- "Resolved endpoints with K8S(...)" - Discovery finds the other servers
- "Executing external script to retrieve value of setting server.cluster.advertised_address"
- "Successfully restarted discovery system"
- Then repeats indefinitely...

**What Never Happens:**
- Cluster formation never completes
- Port 7687 (Bolt) never opens for connections
- Pods never become Ready
- No explicit ERROR messages visible in filtered logs (though we may be missing context)

## What We've Verified

- All pods have matching labels for discovery
- RBAC permissions are correctly configured for K8S API access
- Service account tokens are mounted in pods
- Services route to correct pod IPs
- Network connectivity exists (pods on different nodes, anti-affinity working)
- Helm chart version matches Neo4j version (5.26.16)
- All three servers use identical `neo4j.name` parameter
- `minimumClusterSize=3` is set consistently

## Question

We've followed the official documentation pattern for multi-installation cluster deployment and verified all infrastructure components are correctly configured. Neo4j's discovery mechanism finds the other cluster members, but something prevents the cluster from actually forming.

**What could cause Neo4j to continuously restart its discovery system without progressing to cluster formation and opening the Bolt port?**

Is there a configuration parameter, timing issue, or additional requirement we're missing for the multi-installation pattern on AKS? Any guidance on diagnostic steps or common pitfalls would be greatly appreciated.

---

**Environment:**
- Kubernetes: 1.31 (Azure AKS)
- Neo4j Helm Chart: 5.26.16
- Neo4j Version: 5.26.16 Enterprise
- Azure Region: West Europe
- Node Size: Standard_E4s_v5 (16GB RAM, 4 vCPU)
- Storage: Premium SSD (32GB per pod)
