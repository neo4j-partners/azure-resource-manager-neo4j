# Neo4j Cluster Deployment Best Practices on AKS

**Document Version:** 1.0
**Last Updated:** November 20, 2025
**Status:** Active

---

## Executive Summary

This document explains the **correct approach** for deploying Neo4j clusters on Azure Kubernetes Service (AKS) following official Neo4j best practices, and documents why our initial implementation approach was incorrect.

**Key Finding:** The official neo4j/neo4j Helm chart (v5.26+) **does not support** deploying multi-node clusters via a single Helm installation with `replicas=N`. Instead, it requires **N separate Helm installations** (one per server).

---

## Table of Contents

1. [The Problem](#the-problem)
2. [Why Our Initial Approach Failed](#why-our-initial-approach-failed)
3. [Official Neo4j Approach](#official-neo4j-approach)
4. [Implementation Changes](#implementation-changes)
5. [References](#references)

---

## The Problem

### Initial Implementation Attempt

Our first implementation attempted to deploy a 3-node Neo4j cluster using:

```bicep
// ❌ INCORRECT APPROACH - This doesn't work!
HELM_CMD="$HELM_CMD --set replicas=3"
HELM_CMD="$HELM_CMD --set neo4j.minimumClusterSize=3"
```

**What we expected:**
- Single Helm installation creates a StatefulSet with 3 replicas
- Three pods created: `neo4j-0`, `neo4j-1`, `neo4j-2`
- Pods join together to form a cluster

**What actually happened:**
- Helm installation completed successfully
- StatefulSet was created with **only 1 replica**
- Only one pod was created: `neo4j-0`
- Cluster never formed (can't form quorum with 1 member)

### Investigation Results

After extensive troubleshooting, including:
- ✅ Verified Bicep compilation was working correctly
- ✅ Confirmed the `--set replicas=3` command was in the template
- ✅ Checked that `nodeCount=3` parameter was being passed
- ✅ Implemented pre-compilation to avoid Azure CLI caching issues
- ✅ Verified the Helm command was executed with correct parameters

The StatefulSet **still only created 1 replica**.

---

## Why Our Initial Approach Failed

### Root Cause: Helm Chart Architecture Change

The **official neo4j/neo4j Helm chart** (versions 5.x) uses a fundamentally different architecture than what we assumed:

| Aspect | What We Assumed | Actual Behavior |
|--------|----------------|-----------------|
| **Deployment Model** | Single Helm installation | One installation per server |
| **StatefulSet** | One StatefulSet with N replicas | N StatefulSets with 1 replica each |
| **Replicas Parameter** | Controls cluster size | **Does not exist / ignored** |
| **Cluster Formation** | Automatic via StatefulSet | Via shared `neo4j.name` parameter |
| **Release Names** | One release | N releases (server-1, server-2, server-3) |

### Helm Chart Parameter Reality

From official Neo4j documentation research:

```yaml
# ❌ These parameters DO NOT EXIST in neo4j/neo4j chart v5.26
replicas: 3
core.numberOfServers: 3

# ✅ These parameters DO EXIST and are required
neo4j:
  name: "my-cluster"              # Cluster identifier
  minimumClusterSize: 3           # How many servers must join
  password: "password"
  edition: "enterprise"
  acceptLicenseAgreement: "yes"
```

**Critical insight:** The `neo4j.minimumClusterSize` parameter tells Neo4j how many cluster members to **wait for** before becoming operational, but it does **NOT** control how many pods/servers are created.

### Historical Context

The **older community Helm chart** (`helm/charts/stable/neo4j`) DID support this pattern:

```yaml
# ✅ This worked in OLD helm/charts/stable/neo4j
core:
  numberOfServers: 3    # Created StatefulSet with 3 replicas
  standalone: false
```

However, the **official Neo4j Helm chart** (`neo4j/neo4j`) changed this architecture when they took over maintenance.

---

## Official Neo4j Approach

### Per the Neo4j Kubernetes Operations Manual

**Source:** https://neo4j.com/docs/operations-manual/current/kubernetes/quickstart-cluster/

The official approach for deploying a 3-node cluster is:

1. **Create three separate values files:**
   - `server-1.values.yaml`
   - `server-2.values.yaml`
   - `server-3.values.yaml`

2. **Install the Helm chart three times:**

   ```bash
   # Server 1
   helm install server-1 neo4j/neo4j \
     --namespace neo4j \
     --values server-1.values.yaml

   # Server 2
   helm install server-2 neo4j/neo4j \
     --namespace neo4j \
     --values server-2.values.yaml

   # Server 3
   helm install server-3 neo4j/neo4j \
     --namespace neo4j \
     --values server-3.values.yaml
   ```

3. **Each values file shares the cluster name:**

   ```yaml
   # All three files contain:
   neo4j:
     name: "my-cluster"          # ← Same cluster name
     minimumClusterSize: 3        # ← Same minimum size
     password: "same-password"    # ← Same password
   ```

### What Each Installation Creates

Each `helm install` command creates:

| Resource | Count | Name Pattern |
|----------|-------|--------------|
| StatefulSet | 1 | `server-N` |
| Pod | 1 | `server-N-0` |
| Headless Service | 1 | `server-N` |
| ServiceAccount | 1 | `server-N` |
| ConfigMaps | Multiple | `server-N-*` |
| Secrets | Multiple | `server-N-*` |
| PVC | 1 | `data-server-N-0` |

**Total for 3-node cluster:** 3 StatefulSets, 3 pods, 3 headless services, etc.

### How Cluster Formation Works

1. **Each server starts independently** and looks for other servers with:
   - Same `neo4j.name` value ("my-cluster")
   - Kubernetes service discovery (K8S resolver)

2. **Servers discover each other** via Kubernetes API:
   - ServiceAccounts grant permission to list services
   - Neo4j queries for services with matching labels
   - Servers connect using discovery port (6000)

3. **Quorum is established** when `minimumClusterSize` servers join:
   - With `minimumClusterSize=3`, all 3 must join before cluster becomes operational
   - Cluster elects a leader
   - Database becomes available

---

## Implementation Changes

### Bicep Architecture Changes

#### Before (Incorrect):

```bicep
// Single deployment script resource
resource helmDeployment 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'helm-install-${uniqueString(...)}'
  properties: {
    scriptContent: '''
      if [ "$IS_CLUSTER" == "true" ]; then
        HELM_CMD="$HELM_CMD --set replicas=$NODE_COUNT"  // ❌ Ignored!
        HELM_CMD="$HELM_CMD --set neo4j.minimumClusterSize=$NODE_COUNT"
      fi

      # Single Helm install
      helm upgrade --install neo4j neo4j/neo4j ...
    '''
  }
}
```

**Result:** 1 StatefulSet with 1 replica (not 3)

#### After (Correct):

```bicep
// Three separate deployment script resources
resource helmDeploymentServer1 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'helm-install-server-1-${uniqueString(...)}'
  properties: {
    scriptContent: '''
      helm upgrade --install server-1 neo4j/neo4j \
        --set neo4j.name=neo4j-cluster \
        --set neo4j.minimumClusterSize=3 \
        ...
    '''
  }
}

resource helmDeploymentServer2 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'helm-install-server-2-${uniqueString(...)}'
  properties: {
    scriptContent: '''
      helm upgrade --install server-2 neo4j/neo4j \
        --set neo4j.name=neo4j-cluster \
        --set neo4j.minimumClusterSize=3 \
        ...
    '''
  }
  dependsOn: [helmDeploymentServer1]  // Sequential deployment
}

resource helmDeploymentServer3 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'helm-install-server-3-${uniqueString(...)}'
  properties: {
    scriptContent: '''
      helm upgrade --install server-3 neo4j/neo4j \
        --set neo4j.name=neo4j-cluster \
        --set neo4j.minimumClusterSize=3 \
        ...
    '''
  }
  dependsOn: [helmDeploymentServer2]  // Sequential deployment
}
```

**Result:** 3 StatefulSets, each with 1 replica (3 total pods)

### Alternative: Loop-Based Approach

Instead of three separate resources, use Bicep's array iteration:

```bicep
var clusterMembers = [ 'server-1', 'server-2', 'server-3' ]

resource helmDeployment 'Microsoft.Resources/deploymentScripts@2023-08-01' = [for (member, index) in clusterMembers: {
  name: 'helm-install-${member}-${uniqueString(...)}'
  properties: {
    environmentVariables: [
      {
        name: 'SERVER_NAME'
        value: member
      }
      {
        name: 'SERVER_INDEX'
        value: string(index)
      }
    ]
    scriptContent: '''
      helm upgrade --install $SERVER_NAME neo4j/neo4j \
        --set neo4j.name=neo4j-cluster \
        --set neo4j.minimumClusterSize=3 \
        ...
    '''
  }
  dependsOn: index == 0 ? [] : [helmDeployment[index - 1]]  // Sequential
}]
```

**Benefits:**
- ✅ Scales to any nodeCount (3, 5, 7, etc.)
- ✅ DRY principle (no code duplication)
- ✅ Sequential deployment via dependsOn chain

### Key Parameter Changes

| Parameter | Before | After | Reason |
|-----------|--------|-------|--------|
| `replicas` | `--set replicas=3` | **Removed** | Not supported by chart |
| `neo4j.name` | Not set | `--set neo4j.name=neo4j-cluster` | Required for cluster formation |
| `neo4j.minimumClusterSize` | Set correctly | Keep as-is | Tells Neo4j how many to wait for |
| Release name | `neo4j` | `server-1`, `server-2`, `server-3` | Each installation needs unique name |

---

## References

### Official Neo4j Documentation

1. **Neo4j Kubernetes Operations Manual**
   https://neo4j.com/docs/operations-manual/current/kubernetes/

2. **Quickstart: Deploy a Cluster**
   https://neo4j.com/docs/operations-manual/current/kubernetes/quickstart-cluster/

3. **Create Helm Deployment Values Files**
   https://neo4j.com/docs/operations-manual/current/kubernetes/quickstart-cluster/create-value-file/

4. **Install Neo4j Cluster Servers**
   https://neo4j.com/docs/operations-manual/current/kubernetes/quickstart-cluster/install-servers/

### Key Quotes from Documentation

> "Create a Helm deployment values.yaml file for **each Neo4j cluster member** with all the configuration settings."
> — Neo4j Kubernetes Operations Manual

> "All Neo4j cluster servers are linked together by the value of the parameter `neo4j.name`."
> — Neo4j Kubernetes Operations Manual

> "When installed via the Neo4j Helm chart, they will join the cluster identified by `neo4j.name`."
> — Neo4j Kubernetes Operations Manual

### Historical Context

The older **Labs Helm Chart** (deprecated) did support `core.numberOfServers`:

- GitHub: https://github.com/helm/charts/tree/master/stable/neo4j (archived)
- Used StatefulSet with replicas parameter
- Replaced by official neo4j/neo4j chart in 2021

---

## Lessons Learned

### What Went Wrong

1. **Assumed StatefulSet pattern** - We assumed Neo4j would follow standard Kubernetes StatefulSet patterns
2. **Didn't verify Helm chart parameters** - We added `--set replicas=3` without checking if it existed
3. **Relied on community knowledge** - Older blog posts and Stack Overflow answers reference the deprecated chart
4. **Didn't read official docs first** - Should have started with Neo4j Operations Manual

### What Went Right

1. **Systematic debugging** - We methodically eliminated caching, compilation, and parameter passing issues
2. **Official documentation research** - Eventually found the correct approach in official docs
3. **Understanding root cause** - Identified architectural difference rather than a bug

### Best Practices for Future Work

1. **✅ Always start with official vendor documentation** - Don't assume patterns
2. **✅ Verify Helm chart parameters** - Use `helm show values` to inspect actual parameters
3. **✅ Test assumptions early** - Deploy manually first to validate approach
4. **✅ Check deprecation notices** - Old charts may have different architectures
5. **✅ Document architectural decisions** - Explain why we chose this approach

---

## Cluster Discovery: DNS vs K8S Resolver

### Overview

Neo4j supports two primary discovery mechanisms for Kubernetes clusters:

| Resolver Type | Description | Configuration |
|---------------|-------------|---------------|
| **K8S** | Uses Kubernetes API to list services | `dbms.cluster.discovery.resolver_type=K8S` |
| **DNS** | Uses DNS A records from headless service | `dbms.cluster.discovery.resolver_type=DNS` |

### K8S Resolver (Helm Chart Default)

The official Neo4j Helm chart defaults to K8S resolver:

```yaml
dbms.cluster.discovery.resolver_type: K8S
dbms.kubernetes.discovery.service_port_name: tcp-tx
dbms.kubernetes.label_selector: app=<cluster-name>,helm.neo4j.com/service=internals,helm.neo4j.com/clustering=true
```

**Requirements:**
- ServiceAccount with RBAC permissions to list services
- Service account token mounting enabled (`automountServiceAccountToken=true`)
- May conflict with AKS Workload Identity

### DNS Resolver (Current Implementation)

Our implementation uses DNS resolver for simpler cluster discovery:

```yaml
dbms.cluster.discovery.resolver_type: DNS
dbms.cluster.discovery.endpoints: <cluster-name>-internals.<namespace>.svc.cluster.local:6000
```

**Advantages:**
- Simpler configuration - no RBAC/ServiceAccount requirements
- Uses standard Kubernetes DNS
- Works seamlessly with AKS Workload Identity
- No special permissions needed

**How it works:**
1. Each Neo4j server starts and queries the DNS endpoint
2. DNS returns A records for all pods backing the headless/internals service
3. Servers use these IPs to connect on discovery port 6000
4. Cluster forms when `minimumClusterSize` members join

### Configuration in helm-deployment.bicep

```bash
# DNS endpoint for cluster discovery
DNS_ENDPOINT="${CLUSTER_NAME}-internals.${NAMESPACE_NAME}.svc.cluster.local:6000"

# Set in neo4j-config-values.yaml
config:
  dbms.cluster.discovery.resolver_type: "DNS"
  dbms.cluster.discovery.endpoints: "$DNS_ENDPOINT"
```

---

## Conclusion

The Neo4j official Helm chart requires **three separate installations** to deploy a 3-node cluster, not a single installation with `replicas=3`. This is **by design** per the Neo4j Kubernetes Operations Manual and is the **only supported approach** for the neo4j/neo4j Helm chart v5.x.

Our implementation uses **DNS-based discovery** instead of the K8S API resolver for simpler configuration and better compatibility with AKS Workload Identity.

---

**Document Maintainer:** Claude Code
**Review Status:** Updated with DNS resolver documentation
**Last Updated:** November 2025
**Next Review:** After successful 3-node cluster deployment
