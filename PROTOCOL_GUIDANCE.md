# Neo4j Connection Protocol Guidance

## Overview
This document explains the difference between bolt:// and neo4j:// connection protocols, and provides guidance on which protocol to use for Enterprise and Community editions.

## Protocol Comparison

### bolt:// Protocol (Direct Connection)

**What it does:**
- Direct connection to a specific Neo4j server
- No routing table lookup
- No discovery protocol
- Simple point-to-point connection

**Ports required:**
- 7687 (Bolt)

**Use cases:**
- Single server (standalone) deployments
- When you know the exact server address
- Development and testing environments
- Most secure option (minimal ports exposed)

**Example:**
```
bolt://hostname:7687
```

**Connection behavior:**
1. Client connects directly to hostname:7687
2. No routing table queries
3. All transactions go to this specific server
4. Simple and predictable

### neo4j:// Protocol (Routing Connection)

**What it does:**
- Routing-aware connection for clustered deployments
- Queries routing table from server
- Discovers cluster topology
- Load balances across cluster members
- Automatically handles cluster changes

**Ports required:**
- 7687 (Bolt)
- 7688 (Bolt Routing) - for routing table queries
- 5000 (Discovery) - for cluster member discovery (internal only)

**Use cases:**
- Cluster deployments (3+ servers)
- When you want automatic failover
- When you need load balancing
- When cluster topology might change

**Example:**
```
neo4j://hostname:7687
```

**Connection behavior:**
1. Client connects to hostname:7687
2. Issues routing table query on port 7688
3. Receives list of cluster members and their roles
4. Routes read/write transactions appropriately
5. Periodically refreshes routing table

## Why neo4jtester Might Have Worked Without Port 7688

### Possible Explanations

**1. Go Driver Fallback Behavior**
The Go Neo4j driver (used by neo4jtester) may have different fallback logic than Python driver:
- Attempts routing query on port 7688
- If routing fails, falls back to direct bolt connection
- More permissive error handling
- Designed for compatibility

**2. Python Driver Stricter**
The Python driver (neo4j==5.28.2) used in validate_deploy may be stricter:
- Requires routing to succeed when using neo4j:// scheme
- Fails fast if routing table unavailable
- More explicit about routing requirements
- Designed for correctness over compatibility

**3. Driver Version Evolution**
- Older drivers: More permissive, auto-fallback
- Newer drivers: Stricter validation, explicit requirements
- neo4jtester may use older/different Go driver version
- Python 5.28.2 is recent and strict

## Recommendations by Edition and Deployment Type

### Neo4j Community Edition

**Community = Always Standalone (Single Server)**

Recommendation: **Use bolt://**

Reasoning:
- Community edition does not support clustering
- Always single server deployment
- No routing needed
- More secure (no port 7688 exposure needed)
- Simpler configuration
- Matches actual deployment architecture

**Files to update:**
- `deployments/src/orchestrator.py` - Use bolt:// for community scenarios
- `marketplace/neo4j-community/modules/network.bicep` - Remove port 7688 rule
- Documentation - Specify bolt:// in examples

### Neo4j Enterprise Edition

**Enterprise = Standalone OR Cluster**

Recommendation: **Use protocol based on nodeCount**

**For Standalone (nodeCount = 1):**
- Use: `bolt://`
- Reasoning: Single server, no routing needed
- Security: No port 7688 exposure needed

**For Cluster (nodeCount >= 3):**
- Use: `neo4j://`
- Reasoning: Multi-server, routing needed for load balancing
- Security: Port 7688 exposure required
- Benefits: Automatic failover, load distribution

**Implementation:**
```python
# In orchestrator.py
if node_count == 1:
    protocol = "bolt"
else:
    protocol = "neo4j"

neo4j_uri = f"{protocol}://{hostname}:7687"
```

**Network Security:**
- Standalone: Expose only 22, 7473, 7474, 7687
- Cluster: Expose 22, 7473, 7474, 7687, 7688 (Internet)
- Cluster: Expose 5000, 6000, 7000 (VirtualNetwork only)

## Current State Analysis

### Community Edition
- **Current code:** Uses neo4j:// protocol
- **Current ports:** Exposes 7688 to Internet
- **Correct approach:** Use bolt://, don't expose 7688
- **Action needed:** Change protocol to bolt://

### Enterprise Edition
- **Current code:** Uses neo4j:// protocol for all deployments
- **Current ports:** Exposes 7688 to Internet for all deployments
- **Correct approach:** Use bolt:// for standalone, neo4j:// for cluster
- **Action needed:** Make protocol conditional on nodeCount

## Security Best Practices

### Principle: Minimal Necessary Exposure

**For Standalone Deployments (Community + Enterprise nodeCount=1):**
```
Exposed to Internet:
- 22 (SSH) - For administration
- 7473 (HTTPS) - For browser (optional, can be disabled)
- 7474 (HTTP) - For browser
- 7687 (Bolt) - For database connections

NOT exposed:
- 7688 (Routing) - Not needed for standalone
- 5000 (Discovery) - Not needed for standalone
```

**For Cluster Deployments (Enterprise nodeCount>=3):**
```
Exposed to Internet:
- 22 (SSH) - For administration
- 7473 (HTTPS) - For browser (optional)
- 7474 (HTTP) - For browser
- 7687 (Bolt) - For database connections
- 7688 (Routing) - Required for cluster-aware drivers

Exposed to VirtualNetwork only:
- 5000 (Discovery) - Cluster member discovery
- 6000 (Cluster Communication) - Transaction shipping
- 7000 (Raft) - Consensus protocol

NOT exposed to Internet:
- 5000, 6000, 7000 - Internal cluster communication only
```

## Implementation Checklist

### For Community Edition
- [ ] Change orchestrator.py to use bolt:// protocol
- [ ] Remove port 7688 from network.bicep
- [ ] Update documentation to show bolt:// examples
- [ ] Remove routing configuration from cloud-init
- [ ] Test validation with bolt://

### For Enterprise Edition
- [ ] Make protocol conditional: bolt:// for standalone, neo4j:// for cluster
- [ ] Keep port 7688 in network.bicep (needed for clusters)
- [ ] Update documentation to explain both protocols
- [ ] Keep routing configuration in cloud-init (needed for clusters)
- [ ] Test both standalone and cluster validation

### For Deployment Scripts
- [ ] Update validate_deploy to accept protocol parameter
- [ ] Update orchestrator.py to choose protocol based on edition/nodeCount
- [ ] Update models.py to allow both protocols in URI field
- [ ] Update GitHub Actions workflows to use correct protocol
- [ ] Document protocol selection logic

## Testing Plan

### Test 1: Community with bolt://
- Deploy community standalone
- No port 7688 exposed
- Validate with bolt://hostname:7687
- Should succeed

### Test 2: Enterprise Standalone with bolt://
- Deploy enterprise nodeCount=1
- No port 7688 exposed
- Validate with bolt://hostname:7687
- Should succeed

### Test 3: Enterprise Cluster with neo4j://
- Deploy enterprise nodeCount=3
- Port 7688 exposed to Internet
- Validate with neo4j://hostname:7687
- Should succeed with routing

### Test 4: Backward Compatibility
- Test neo4j:// on standalone (should it work or fail?)
- Document expected behavior
- Decide if fallback is acceptable

## References

- Neo4j Driver Documentation: https://neo4j.com/docs/drivers/
- Routing Table Protocol: https://neo4j.com/docs/bolt/current/
- Cluster Architecture: https://neo4j.com/docs/operations-manual/current/clustering/
- Security Best Practices: https://neo4j.com/docs/operations-manual/current/security/

## Decision Log

**Date: 2025-11-20**
**Status: ✅ IMPLEMENTED**

**Implementation completed:**
1. ✅ bolt:// for all standalone deployments (Community + Enterprise nodeCount=1)
2. ✅ neo4j:// only for cluster deployments (Enterprise nodeCount>=3)
3. ✅ Protocol selection logic implemented in orchestrator.py
4. ✅ Network security groups updated (port 7688 removed from Community)
5. ✅ All documentation and examples updated

**Files modified:**
- `deployments/src/orchestrator.py` - Added conditional protocol logic (line 506-547)
- `deployments/src/models.py` - Updated URI field description (line 218)
- `deployments/src/validate_deploy.py` - Updated examples to use bolt:// for standalone
- `marketplace/neo4j-community/modules/network.bicep` - Removed port 7688
- `marketplace/neo4j-community/mainTemplate.json` - Rebuilt from updated Bicep

**Testing:**
Protocol selection logic verified:
- Community (any nodeCount): ✅ bolt://
- Enterprise standalone (nodeCount=1): ✅ bolt://
- Enterprise cluster (nodeCount>=3): ✅ neo4j://
- AKS cluster (nodeCount>=3): ✅ neo4j://
