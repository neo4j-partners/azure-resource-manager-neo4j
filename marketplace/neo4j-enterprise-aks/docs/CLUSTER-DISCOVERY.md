# Neo4j Cluster Discovery Resolvers

## Overview

A **resolver** determines how Neo4j's discovery service finds other servers in the cluster. The `dbms.cluster.discovery.resolver_type` configuration setting controls which discovery mechanism Neo4j uses during cluster formation and member discovery.

Neo4j supports **four resolver types**, each suited to different deployment scenarios:
- **LIST** - Hard-coded server addresses
- **DNS** - DNS A record lookups
- **SRV** - DNS Service (SRV) record lookups
- **K8S** - Kubernetes native service discovery

**Official Documentation:** https://neo4j.com/docs/operations-manual/current/clustering/setup/discovery/

---

## 1. LIST Resolver (Hard-coded Addresses)

### Configuration
```properties
dbms.cluster.discovery.resolver_type=LIST
server.cluster.advertised_address=server01.example.com:6000
dbms.cluster.endpoints=server01.example.com:6000,server02.example.com:6000,server03.example.com:6000
```

### How It Works
- Uses a **hard-coded list** of server addresses directly in the configuration
- No DNS lookups performed
- Each server explicitly lists all cluster members
- Most straightforward approach - "what you specify is what Neo4j uses"

### Advantages
- ✅ Simple and predictable
- ✅ No DNS dependencies
- ✅ Clear and explicit configuration
- ✅ Works in environments without DNS

### Limitations
- ❌ Not flexible when servers are replaced or addresses change dynamically
- ❌ Requires manual configuration updates for cluster topology changes
- ❌ Static configuration not ideal for cloud-native environments

### Use Cases
- Simple, static deployments
- Development/testing environments
- Environments without DNS infrastructure
- Fixed infrastructure with stable addresses

### Example (3-node cluster)
```properties
# Server 1
dbms.cluster.discovery.resolver_type=LIST
server.cluster.advertised_address=10.0.1.10:6000
dbms.cluster.endpoints=10.0.1.10:6000,10.0.1.11:6000,10.0.1.12:6000

# Server 2
dbms.cluster.discovery.resolver_type=LIST
server.cluster.advertised_address=10.0.1.11:6000
dbms.cluster.endpoints=10.0.1.10:6000,10.0.1.11:6000,10.0.1.12:6000

# Server 3
dbms.cluster.discovery.resolver_type=LIST
server.cluster.advertised_address=10.0.1.12:6000
dbms.cluster.endpoints=10.0.1.10:6000,10.0.1.11:6000,10.0.1.12:6000
```

---

## 2. DNS Resolver (DNS A Records)

### Configuration
```properties
dbms.cluster.discovery.resolver_type=DNS
server.cluster.advertised_address=server01.example.com:6000
dbms.cluster.endpoints=cluster01.example.com:6000
```

### How It Works
- Uses **DNS A records** to resolve cluster member IP addresses
- DNS lookup performed during startup
- Domain name returns an A record for every server in the cluster
- Each A record contains the IP address of a cluster member
- All resolved IPs are used to join or form the cluster

### Requirements
- ✅ All servers must use the **same discovery port** (specified in endpoints)
- ✅ DNS A records must be configured for the cluster domain
- ✅ DNS must return multiple A records for the cluster domain

### Advantages
- ✅ Dynamic IP address resolution
- ✅ Simpler configuration than LIST (single domain vs. multiple addresses)
- ✅ DNS updates automatically propagate to cluster members
- ✅ Good for cloud environments with dynamic IPs

### Limitations
- ❌ All servers must use the same port (less flexible than SRV)
- ❌ Requires DNS infrastructure
- ❌ DNS caching may delay topology changes

### Use Cases
- Cloud deployments with dynamic IPs
- Environments with consistent port assignments
- Infrastructure with DNS management automation

### Example DNS Configuration

**DNS A Records:**
```
cluster01.example.com.  IN A  10.0.1.10
cluster01.example.com.  IN A  10.0.1.11
cluster01.example.com.  IN A  10.0.1.12
```

**Neo4j Configuration (all servers):**
```properties
dbms.cluster.discovery.resolver_type=DNS
server.cluster.advertised_address=server01.example.com:6000  # Server 1
# server.cluster.advertised_address=server02.example.com:6000  # Server 2
# server.cluster.advertised_address=server03.example.com:6000  # Server 3
dbms.cluster.endpoints=cluster01.example.com:6000
```

**From Neo4j Docs:**
> "When a DNS lookup is performed, the domain name returns an A record for every server in the cluster where each A record contains the IP address of the server, and the configured server uses all the IP addresses from the A records to join or form a cluster."

---

## 3. SRV Resolver (DNS Service Records)

### Configuration
```properties
dbms.cluster.discovery.resolver_type=SRV
server.cluster.advertised_address=server01.example.com:6000
dbms.cluster.endpoints=cluster01.example.com:0
```

### How It Works
- Uses **DNS SRV records** to discover cluster members
- SRV records contain **both hostname/IP AND port information**
- Allows **different discovery ports** across cluster members
- Port in `dbms.cluster.endpoints` **must be set to 0** (actual port comes from SRV record)
- DNS lookup returns complete service information (host + port)

### Requirements
- ✅ DNS SRV records must be configured
- ✅ `dbms.cluster.endpoints` port **must be 0**
- ✅ SRV records must include priority, weight, port, and target

### Advantages
- ✅ Supports **different ports** for different cluster members
- ✅ More flexible than DNS A records
- ✅ **Ideal for Kubernetes/container environments**
- ✅ Native support in Kubernetes headless services
- ✅ Industry-standard service discovery mechanism

### Limitations
- ❌ Requires SRV record configuration (more complex than A records)
- ❌ Not all DNS providers support SRV records easily
- ❌ Requires understanding of SRV record format

### Use Cases
- **Kubernetes deployments with headless services**
- Multi-port cluster configurations
- Cloud-native architectures
- Service mesh environments

### Example DNS SRV Configuration

**DNS SRV Records:**
```
_discovery._tcp.cluster01.example.com.  IN SRV 0 0 6000 server01.example.com.
_discovery._tcp.cluster01.example.com.  IN SRV 0 0 6000 server02.example.com.
_discovery._tcp.cluster01.example.com.  IN SRV 0 0 6001 server03.example.com.
```

**SRV Record Format:**
```
_service._proto.name.  TTL  class  SRV priority weight port target
```

**Neo4j Configuration:**
```properties
dbms.cluster.discovery.resolver_type=SRV
server.cluster.advertised_address=server01.example.com:6000
dbms.cluster.endpoints=cluster01.example.com:0  # Port MUST be 0!
```

**From Neo4j Docs:**
> "The SRV record returned by DNS should contain the IP address or hostname and the cluster port for the servers to be discovered, and the configured server uses all the addresses from the SRV record to join or form a cluster."

### Kubernetes Example

For a Neo4j StatefulSet with headless service:

**Kubernetes Service (creates SRV records automatically):**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: neo4j
  namespace: default
spec:
  clusterIP: None  # Headless service
  selector:
    app: neo4j
  ports:
  - name: discovery
    port: 6000
    targetPort: 6000
```

**Kubernetes automatically creates SRV records:**
```
_discovery._tcp.neo4j.default.svc.cluster.local.  IN SRV 0 0 6000 neo4j-0.neo4j.default.svc.cluster.local.
_discovery._tcp.neo4j.default.svc.cluster.local.  IN SRV 0 0 6000 neo4j-1.neo4j.default.svc.cluster.local.
_discovery._tcp.neo4j.default.svc.cluster.local.  IN SRV 0 0 6000 neo4j-2.neo4j.default.svc.cluster.local.
```

**Neo4j Configuration:**
```properties
dbms.cluster.discovery.resolver_type=SRV
server.cluster.advertised_address=neo4j-0.neo4j.default.svc.cluster.local:6000
dbms.cluster.endpoints=_discovery._tcp.neo4j.default.svc.cluster.local:0
```

---

## 4. K8S Resolver (Kubernetes Native)

### Configuration
```properties
dbms.cluster.discovery.resolver_type=K8S
dbms.kubernetes.label_selector=app=neo4j,cluster=production
dbms.kubernetes.discovery.service_port_name=discovery
server.cluster.advertised_address=neo4j-0.neo4j.default.svc.cluster.local:6000
```

### How It Works
- Uses **Kubernetes List Service API** to discover cluster members
- Queries Kubernetes API directly (no DNS involved)
- Filters services based on label selector
- Most cloud-native approach for Kubernetes deployments
- `dbms.cluster.endpoints` is **ignored** in this mode

### Requirements
- ✅ Pod service account must have **permission to list services**
- ✅ `server.cluster.advertised_address` must use K8s internal DNS format: `<service-name>.<namespace>.svc.cluster.local`
- ✅ Services must be labeled correctly for label selector
- ✅ Service port must be named in service definition

### Advantages
- ✅ **Native Kubernetes integration**
- ✅ No DNS configuration required
- ✅ Dynamic service discovery via K8s API
- ✅ Label-based filtering for multi-cluster environments
- ✅ Most flexible for Kubernetes deployments

### Limitations
- ❌ Requires Kubernetes RBAC configuration
- ❌ Only works in Kubernetes (not portable)
- ❌ Additional API calls to Kubernetes control plane

### Use Cases
- **Production Kubernetes/AKS deployments** (recommended)
- Multi-tenant Kubernetes clusters
- GitOps-managed infrastructure
- Cloud-native architectures with service mesh

### Required RBAC Configuration

**ServiceAccount:**
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: neo4j-sa
  namespace: default
```

**Role:**
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: neo4j-service-reader
  namespace: default
rules:
- apiGroups: [""]
  resources: ["services"]
  verbs: ["get", "list", "watch"]
```

**RoleBinding:**
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: neo4j-service-reader-binding
  namespace: default
subjects:
- kind: ServiceAccount
  name: neo4j-sa
  namespace: default
roleRef:
  kind: Role
  name: neo4j-service-reader
  apiGroup: rbac.authorization.k8s.io
```

### Example Kubernetes Configuration

**StatefulSet with K8S resolver:**
```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: neo4j
spec:
  serviceName: neo4j
  replicas: 3
  selector:
    matchLabels:
      app: neo4j
  template:
    metadata:
      labels:
        app: neo4j
        cluster: production
    spec:
      serviceAccountName: neo4j-sa  # RBAC permissions
      containers:
      - name: neo4j
        image: neo4j:5-enterprise
        env:
        - name: NEO4J_dbms_cluster_discovery_resolver__type
          value: "K8S"
        - name: NEO4J_dbms_kubernetes_label__selector
          value: "app=neo4j,cluster=production"
        - name: NEO4J_dbms_kubernetes_discovery_service__port__name
          value: "discovery"
        - name: NEO4J_server_cluster_advertised__address
          value: "$(hostname).neo4j.default.svc.cluster.local:6000"
```

**Service Definition:**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: neo4j
  namespace: default
  labels:
    app: neo4j
    cluster: production
spec:
  clusterIP: None  # Headless
  selector:
    app: neo4j
  ports:
  - name: discovery  # Must match service_port_name
    port: 6000
  - name: bolt
    port: 7687
  - name: http
    port: 7474
```

---

## Important Changes in Neo4j 2025

### Port Changes
> "Port 5000 is no longer used from 2025.01 onwards, and **port 6000 should be used for internal traffic**."

**Old (before 2025):**
```properties
server.cluster.raft.advertised_address=server01.example.com:5000
```

**New (2025 onwards):**
```properties
server.cluster.advertised_address=server01.example.com:6000
```

### Removed Settings
> "In 2025.01, the settings `server.discovery.advertised_address` and `server.discovery.listen_address` are **removed**. To list the discovery endpoints, use the value from the `server.cluster.advertised_address` setting."

**Old (deprecated):**
```properties
server.discovery.advertised_address=server01.example.com:5000
server.discovery.listen_address=0.0.0.0:5000
```

**New (2025):**
```properties
server.cluster.advertised_address=server01.example.com:6000
server.cluster.listen_address=0.0.0.0:6000
```

---

## Resolver Type Comparison

| Feature | LIST | DNS | SRV | K8S |
|---------|------|-----|-----|-----|
| **DNS Required** | No | Yes | Yes | No |
| **Dynamic IPs** | ❌ | ✅ | ✅ | ✅ |
| **Different Ports** | ✅ | ❌ | ✅ | ✅ |
| **Kubernetes Native** | ❌ | ❌ | Partial | ✅ |
| **Configuration Complexity** | Low | Medium | Medium | High |
| **Cloud-Native** | ❌ | ⚠️ | ✅ | ✅ |
| **RBAC Required** | No | No | No | Yes |
| **Auto-Discovery** | ❌ | ✅ | ✅ | ✅ |
| **Topology Changes** | Manual | Auto | Auto | Auto |

---

## Recommendations for AKS/Kubernetes

### For Production AKS Deployments

**Best Choice: K8S Resolver** ✅
```properties
dbms.cluster.discovery.resolver_type=K8S
dbms.kubernetes.label_selector=app=neo4j
dbms.kubernetes.discovery.service_port_name=discovery
server.cluster.advertised_address=neo4j-0.neo4j.default.svc.cluster.local:6000
```

**Why:**
- Native Kubernetes integration
- Most cloud-native approach
- Automatic service discovery
- Label-based filtering for isolation
- No DNS configuration needed

**Trade-off:** Requires RBAC setup

---

**Alternative: SRV Resolver** ⚠️
```properties
dbms.cluster.discovery.resolver_type=SRV
server.cluster.advertised_address=neo4j-0.neo4j.default.svc.cluster.local:6000
dbms.cluster.endpoints=_discovery._tcp.neo4j.default.svc.cluster.local:0
```

**Why:**
- Works well with Kubernetes headless services
- Kubernetes automatically creates SRV records
- No RBAC configuration needed
- Industry-standard service discovery

**Trade-off:** Relies on DNS (potential caching issues)

---

**Current Implementation: LIST Resolver**
```properties
dbms.cluster.discovery.resolver_type=LIST
dbms.cluster.endpoints=neo4j-0:6000,neo4j-1:6000,neo4j-2:6000
```

**Why used:**
- Simple and predictable
- No dependencies (DNS/RBAC)
- Works for StatefulSet with predictable pod names
- Good for initial implementation

**Limitations:**
- Less cloud-native
- Doesn't handle dynamic topology changes
- Manual configuration for cluster size changes

---

## Migration Path

### Current State (neo4j-enterprise-aks)
The current implementation uses **LIST resolver** (see `marketplace/neo4j-enterprise-aks/docs/HELM-PARAMETER-MAPPING.md:374`):

```yaml
config:
  dbms.cluster.discovery.resolver_type: "LIST"
```

### Recommended Evolution

**Phase 1: Current (LIST)** ✅
- Simple, working implementation
- Good for development and testing
- Establishes baseline functionality

**Phase 2: SRV (Intermediate)**
- Migrate to SRV resolver
- Leverage Kubernetes headless service SRV records
- More cloud-native without RBAC complexity

**Phase 3: K8S (Production-Ready)** 🎯
- Full Kubernetes-native discovery
- Add RBAC configuration
- Production-grade service discovery
- Best practices for enterprise deployments

---

## Testing Resolvers

### Verify DNS Records (for DNS/SRV resolvers)

**Check A Records:**
```bash
nslookup cluster01.example.com
# or
dig cluster01.example.com A +short
```

**Check SRV Records:**
```bash
dig _discovery._tcp.neo4j.default.svc.cluster.local SRV
```

**Expected SRV output:**
```
;; ANSWER SECTION:
_discovery._tcp.neo4j.default.svc.cluster.local. 30 IN SRV 0 0 6000 neo4j-0.neo4j.default.svc.cluster.local.
_discovery._tcp.neo4j.default.svc.cluster.local. 30 IN SRV 0 0 6000 neo4j-1.neo4j.default.svc.cluster.local.
_discovery._tcp.neo4j.default.svc.cluster.local. 30 IN SRV 0 0 6000 neo4j-2.neo4j.default.svc.cluster.local.
```

### Verify Kubernetes Service Discovery (for K8S resolver)

**Check ServiceAccount permissions:**
```bash
kubectl auth can-i list services --as=system:serviceaccount:default:neo4j-sa -n default
# Should return: yes
```

**List services with label selector:**
```bash
kubectl get services -l app=neo4j -n default
```

**Check pod logs for discovery:**
```bash
kubectl logs neo4j-0 -n default | grep -i discovery
```

### Verify Cluster Formation

**Check cluster status:**
```cypher
SHOW SERVERS;
```

**Check cluster topology:**
```cypher
CALL dbms.cluster.overview();
```

---

## Troubleshooting

### LIST Resolver Issues

**Problem:** Cluster members not discovering each other

**Check:**
1. Verify all endpoints are reachable:
   ```bash
   nc -zv server01.example.com 6000
   ```
2. Check firewall rules for port 6000
3. Verify `dbms.cluster.endpoints` lists all members
4. Check logs for connection errors

---

### DNS Resolver Issues

**Problem:** DNS lookup returns no records

**Check:**
1. Verify A records exist:
   ```bash
   dig cluster01.example.com A
   ```
2. Check DNS server configuration
3. Verify all cluster members have A records
4. Test DNS resolution from pod:
   ```bash
   kubectl exec neo4j-0 -- nslookup cluster01.example.com
   ```

---

### SRV Resolver Issues

**Problem:** SRV records not found

**Check:**
1. Verify SRV records exist:
   ```bash
   dig _discovery._tcp.neo4j.default.svc.cluster.local SRV
   ```
2. Ensure `dbms.cluster.endpoints` port is **0**
3. Check headless service configuration (clusterIP: None)
4. Verify service port is named ("discovery")

**Common mistake:**
```properties
# ❌ WRONG - port should be 0 for SRV
dbms.cluster.endpoints=cluster01.example.com:6000

# ✅ CORRECT
dbms.cluster.endpoints=cluster01.example.com:0
```

---

### K8S Resolver Issues

**Problem:** Permission denied when listing services

**Check:**
1. Verify ServiceAccount exists:
   ```bash
   kubectl get sa neo4j-sa -n default
   ```
2. Check RBAC permissions:
   ```bash
   kubectl auth can-i list services --as=system:serviceaccount:default:neo4j-sa -n default
   ```
3. Verify RoleBinding is correct
4. Check pod is using correct ServiceAccount

**Problem:** Services not found by label selector

**Check:**
1. Verify service labels:
   ```bash
   kubectl get svc -n default --show-labels
   ```
2. Check label selector syntax in configuration
3. Ensure service port is named correctly

---

## References

- **Official Documentation:** https://neo4j.com/docs/operations-manual/current/clustering/setup/discovery/
- **Clustering Setup:** https://neo4j.com/docs/operations-manual/current/clustering/setup/deploy/
- **Kubernetes Tutorial:** https://neo4j.com/docs/operations-manual/current/tutorial/tutorial-clustering-docker/
- **Configuration Settings:** https://neo4j.com/docs/operations-manual/current/configuration/configuration-settings/

---

## Summary

**Choose your resolver based on deployment environment:**

| Environment | Recommended Resolver | Rationale |
|-------------|---------------------|-----------|
| **Kubernetes/AKS (Production)** | K8S | Native integration, best for production |
| **Kubernetes/AKS (Simple)** | SRV | Good balance of cloud-native + simplicity |
| **Kubernetes/AKS (Development)** | LIST | Simplest, good for testing |
| **Cloud VMs (Dynamic IPs)** | DNS | Simple DNS-based discovery |
| **Cloud VMs (Different Ports)** | SRV | Flexible port configuration |
| **On-Premise (Static)** | LIST | Simple, no DNS dependencies |
| **Docker Compose** | LIST | Explicit configuration |

**For this codebase (neo4j-enterprise-aks):**
- ✅ **Current:** LIST (simple, working)
- 🎯 **Target:** K8S (production-ready, cloud-native)
- ⚠️ **Intermediate:** SRV (stepping stone)
