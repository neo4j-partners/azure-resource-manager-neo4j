# Enterprise Deployment Differences: Standalone vs Cluster

## Overview
This document details ALL differences between Enterprise standalone (nodeCount=1) and cluster (nodeCount>=3) deployments, not just networking ports.

## Summary: Standalone is NOT Just "Cluster with Fewer Ports"

**Key insight:** Standalone and cluster are fundamentally different architectures, not just different port configurations.

## Complete Differences Matrix

### 1. Network Ports (Internet Exposure)

**Standalone (nodeCount=1):**
```
Exposed to Internet:
- 22 (SSH) - Administration
- 7473 (HTTPS) - Browser
- 7474 (HTTP) - Browser
- 7687 (Bolt) - Database connections
- 7688 (BoltRouting) - Currently exposed, but NOT needed

NOT needed:
- 7688 (Routing) - No cluster to route to
- 6000 (Cluster Communication) - No cluster
- 7000 (Raft Consensus) - No consensus needed
- 5000 (Discovery) - No cluster to discover
```

**Cluster (nodeCount>=3):**
```
Exposed to Internet:
- 22 (SSH) - Administration
- 7473 (HTTPS) - Browser
- 7474 (HTTP) - Browser
- 7687 (Bolt) - Database connections
- 7688 (BoltRouting) - Required for routing table queries

Exposed to VirtualNetwork only:
- 6000 (Cluster Communication) - Transaction shipping between nodes
- 7000 (Raft Consensus) - Leader election, cluster coordination
- 5000 (Discovery) - Cluster member discovery (internal)

NOT exposed to Internet:
- 5000, 6000, 7000 - Security: Internal cluster traffic only
```

### 2. Azure Resources Created

**Standalone (nodeCount=1):**
- Virtual Network (VNet)
- Network Security Group (NSG)
- Managed Identity
- **Single VM** (not VMSS)
- Data disk
- Public IP address (per VM)
- Network Interface

**Cluster (nodeCount>=3):**
- Virtual Network (VNet)
- Network Security Group (NSG)
- Managed Identity
- **Virtual Machine Scale Set (VMSS)** with multiple instances
- Data disks (one per instance)
- **Azure Load Balancer** (added for cluster)
- **Load Balancer Public IP** (added for cluster)
- **Backend address pool** (VMSS instances)
- **Health probes** (port 7474, 7687)
- **Load balancing rules** (distribute traffic)

**Key difference:** Standalone uses individual VMs, cluster uses VMSS + Load Balancer.

### 3. Cloud-Init Scripts

**Standalone uses:** `scripts/neo4j-enterprise/cloud-init/standalone.yaml`
- 121 lines
- Simple configuration
- No cluster setup
- Basic Neo4j configuration
- Sets routing default: `dbms.routing.default_router=SERVER`

**Cluster uses:** `scripts/neo4j-enterprise/cloud-init/cluster.yaml`
- 153 lines (26% more complex)
- **Cluster discovery endpoint generation**
- **Cluster mode configuration**
- **Raft consensus setup**
- Additional cluster-specific settings

### 4. Neo4j Configuration Differences

**Standalone Configuration (standalone.yaml):**
```bash
# Basic server settings
server.default_advertised_address=${PUBLIC_HOSTNAME}
server.bolt.advertised_address=${PUBLIC_HOSTNAME}:7687
server.bolt.listen_address=0.0.0.0:7687

# Routing (basic)
dbms.routing.default_router=SERVER

# NO cluster settings
```

**Cluster Configuration (cluster.yaml):**
```bash
# Basic server settings
server.default_advertised_address=${INTERNAL_HOSTNAME}  # Note: Uses internal hostname
server.bolt.advertised_address=${PUBLIC_HOSTNAME}:7687
server.bolt.listen_address=0.0.0.0:7687

# Cluster mode
server.cluster.system_database_mode=PRIMARY

# Cluster communication (port 6000)
server.cluster.advertised_address=${INTERNAL_HOSTNAME}:6000
server.cluster.listen_address=0.0.0.0:6000

# Raft consensus (port 7000)
server.cluster.raft.advertised_address=${INTERNAL_HOSTNAME}:7000
server.cluster.raft.listen_address=0.0.0.0:7000

# Discovery configuration (port 6000, not 5000!)
dbms.cluster.discovery.version=V2_ONLY
dbms.cluster.discovery.v2.endpoints=${DISCOVERY_ENDPOINTS}
dbms.cluster.minimum_initial_system_primaries_count=${NODE_COUNT}

# Discovery endpoints generated as:
# node000000:6000,node000001:6000,node000002:6000
```

**Critical difference:** Cluster uses internal hostnames for cluster communication, public hostname only for external Bolt.

### 5. Connection Endpoints

**Standalone:**
- Direct connection: `vm0.neo4j-{unique}.{region}.cloudapp.azure.com:7687`
- Single endpoint
- No load balancing
- No failover

**Cluster:**
- Via Load Balancer: `neo4j-lb-{unique}.{region}.cloudapp.azure.com:7687`
- Multiple backend VMs
- Automatic load distribution
- Health probe monitoring
- Failover capability

### 6. Recommended Connection Protocol

**Standalone:**
- **Recommended:** `bolt://hostname:7687`
- Direct connection to single server
- No routing needed
- Simpler and more secure
- Port 7688 not required

**Cluster:**
- **Recommended:** `neo4j://hostname:7687`
- Routing-aware connection
- Queries routing table via port 7688
- Load balancing across cluster members
- Automatic failover on member failure
- Port 7688 required

### 7. High Availability and Failover

**Standalone:**
- ❌ No high availability
- ❌ No automatic failover
- ❌ No load distribution
- ❌ Single point of failure
- Use case: Development, testing, non-critical workloads

**Cluster:**
- ✅ High availability (3+ nodes)
- ✅ Automatic failover (Raft leader election)
- ✅ Load distribution (via routing protocol)
- ✅ Survives single node failure
- Use case: Production, critical workloads

### 8. Read Replica Support

**Standalone (nodeCount=1):**
- ❌ Cannot have read replicas
- Read replicas require cluster architecture

**Cluster (nodeCount>=3):**
- ✅ Can add read replicas (readReplicaCount parameter)
- ✅ Scale read capacity independently
- ✅ Uses separate VMSS for replicas
- Note: Read replicas only supported in Neo4j 4.4 on Azure (v5 uses different architecture)

### 9. Load Balancer Configuration

**Standalone:**
- `loadBalancerCondition = false`
- No load balancer created
- No backend pool
- No health probes
- No load balancing rules

**Cluster:**
- `loadBalancerCondition = true` (when nodeCount >= 3)
- Azure Load Balancer created
- Backend pool with all VMSS instances
- Health probes on ports 7474 and 7687
- Load balancing rules:
  - HTTP (7474) → Backend pool
  - HTTPS (7473) → Backend pool
  - Bolt (7687) → Backend pool
  - Bolt Routing (7688) → Backend pool

### 10. Cost Implications

**Standalone:**
- Single VM cost
- Single data disk
- Single public IP
- No load balancer cost
- Lower total cost

**Cluster:**
- Multiple VMs (3+ instances)
- Multiple data disks (one per instance)
- Load balancer cost (Standard SKU)
- Additional public IP for load balancer
- Significantly higher total cost (3-10x)

### 11. Bicep Template Logic

**File:** `marketplace/neo4j-enterprise/main.bicep`

```bicep
// Line 73: Load balancer conditional
var loadBalancerCondition = ((nodeCount >= 3) || readReplicaEnabledCondition)

// Line 95: Cloud-init selection
var cloudInitTemplate = (nodeCount == 1) ? cloudInitStandalone : cloudInitCluster

// Module deployment
module loadbalancer 'modules/loadbalancer.bicep' = {
  name: 'loadbalancer-deployment'
  params: {
    loadBalancerCondition: loadBalancerCondition  // Creates LB only for cluster
  }
}

module vmss 'modules/vmss.bicep' = {
  name: 'vmss-deployment'
  params: {
    nodeCount: nodeCount                          // Determines VMSS instance count
    cloudInitBase64: cloudInitBase64              // Different config per mode
    loadBalancerBackendAddressPools: loadBalancerBackendAddressPools
  }
}
```

## Why This Matters for Port Configuration

**For Standalone:**
- Opening port 7688 serves no purpose (no cluster to route to)
- Opening ports 6000, 7000, 5000 serves no purpose (no cluster communication)
- These ports should NOT be exposed to reduce attack surface
- Connection should use `bolt://` protocol

**For Cluster:**
- Port 7688 is essential for routing protocol to work
- Ports 6000, 7000, 5000 are essential for internal cluster operations
- These must be configured correctly (VirtualNetwork for internal, Internet for routing)
- Connection should use `neo4j://` protocol

## Recommendation: Protocol Selection Logic

```python
def select_connection_protocol(node_count: int, deployment_type: str) -> str:
    """
    Select appropriate Neo4j connection protocol based on deployment.

    Args:
        node_count: Number of Neo4j nodes
        deployment_type: "VM" (Enterprise) or "COMMUNITY"

    Returns:
        Protocol scheme: "bolt" or "neo4j"
    """
    # Community is always standalone, always use bolt
    if deployment_type == "COMMUNITY":
        return "bolt"

    # Enterprise: conditional based on cluster size
    if node_count == 1:
        return "bolt"   # Standalone: direct connection
    else:
        return "neo4j"  # Cluster: routing connection
```

## Files Affected by Protocol Choice

### If using bolt:// for standalone:
- Update: `deployments/src/orchestrator.py` (line 527) - URI construction
- Update: `marketplace/neo4j-enterprise/modules/network.bicep` - Remove port 7688 for standalone
- Update: `marketplace/neo4j-community/modules/network.bicep` - Remove port 7688
- Keep: Load balancer still determines cluster vs standalone resources

### If using neo4j:// for cluster:
- Keep: Port 7688 in network.bicep (required)
- Keep: Cluster-specific cloud-init configuration
- Keep: Load balancer for cluster deployments

## Summary

**Standalone vs Cluster differences:**

| Aspect | Standalone | Cluster |
|--------|-----------|---------|
| **Architecture** | Single VM | VMSS with 3-10 instances |
| **Load Balancer** | None | Azure Load Balancer |
| **HA/Failover** | No | Yes (Raft consensus) |
| **Connection Protocol** | bolt:// | neo4j:// |
| **Internet Ports** | 22, 7473, 7474, 7687 | 22, 7473, 7474, 7687, 7688 |
| **Internal Ports** | None | 5000, 6000, 7000 |
| **Cloud-Init** | standalone.yaml (121 lines) | cluster.yaml (153 lines) |
| **Neo4j Config** | Basic single-server | Full cluster configuration |
| **Cost** | 1x VM cost | 3-10x VM cost + LB |
| **Use Case** | Dev/test/non-critical | Production/critical |

**Key Takeaway:** Ports are just one of many differences. The entire deployment architecture changes between standalone and cluster.
