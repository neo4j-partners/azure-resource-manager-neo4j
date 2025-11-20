# Security Review - Network Ports and Access Control

## Overview
This document identifies security considerations for Neo4j deployments on Azure, specifically regarding network port exposure and access control policies.

## Historical Context - Main Branch Configuration

### Main Branch Security Posture (Before Migration to Bicep)

**Network Security Groups (Both Editions):**
- File: `marketplace/neo4j-enterprise/mainTemplate.json`
- File: `marketplace/neo4j-community/mainTemplate.json`
- Exposed ports: 22 (SSH), 7473 (HTTPS), 7474 (HTTP), 7687 (Bolt)
- NOT exposed: 7688 (Routing), 5000 (Discovery)

**Routing Configuration (Both Editions):**
- File: `scripts/neo4j-enterprise/node.sh`
- File: `scripts/neo4j-community/node.sh`
- Routing addresses configured with privateIP only
- Discovery addresses configured with privateIP only
- Port 7688 and 5000 NOT accessible from Internet

**Impact of Main Branch Configuration:**
- More secure - minimal port exposure
- Routing protocol (neo4j://) would NOT work from outside Azure
- Users would need to use bolt:// protocol for external connections
- Internal cluster communication used port 5000 on private network

### Current Branch Changes

The migration to Bicep and cloud-init introduced routing accessibility:
- Port 7688 now exposed to Internet (both editions)
- Routing can work with neo4j:// protocol from external clients
- Port 5000 initially exposed in community (now fixed)
- Trade-off: Increased functionality vs increased attack surface

## Critical Finding: Port 5000 Exposure Difference

### Current State

**Enterprise Edition** (marketplace/neo4j-enterprise/modules/network.bicep):
- Port 7688 (Bolt Routing): Open to Internet
- Port 5000 (Discovery): NOT exposed to Internet
- Port 6000 (Cluster Communication): VirtualNetwork only
- Port 7000 (Raft Consensus): VirtualNetwork only

**Community Edition** (marketplace/neo4j-community/modules/network.bicep):
- Port 7688 (Routing): Open to Internet
- Port 5000 (Discovery): Open to Internet ⚠️ SECURITY CONCERN

### Security Implications

**Port 5000 (Discovery):**
- Used for Neo4j cluster discovery protocol
- In Enterprise, this port is NOT exposed to public Internet
- Community edition currently exposes it to Internet
- This creates an inconsistency between editions
- Exposing discovery protocol to Internet increases attack surface

**Port 7688 (Routing):**
- Used for Bolt routing protocol
- Both editions expose this to Internet
- Required for neo4j:// protocol to work with cluster-aware drivers
- Legitimate use case for public access

## Routing Configuration Differences

### Enterprise Standalone Configuration
File: scripts/neo4j-enterprise/cloud-init/standalone.yaml

- Only sets: dbms.routing.default_router=SERVER
- Does NOT explicitly configure routing advertised addresses
- Does NOT explicitly configure discovery addresses
- Simpler configuration with less exposed metadata

### Community Standalone Configuration
File: scripts/neo4j-community/cloud-init/standalone.yaml

- Sets: dbms.routing.default_router=SERVER
- Explicitly configures: server.routing.advertised_address using PUBLIC_HOSTNAME
- Explicitly configures: server.discovery.advertised_address using PUBLIC_HOSTNAME
- More verbose configuration with more exposed endpoints

## Recommendation: Align Community with Enterprise Security Model

### Action Items

1. **Remove Port 5000 from Community Internet Access**
   - File: marketplace/neo4j-community/modules/network.bicep
   - Either remove port 5000 rule entirely, or restrict to VirtualNetwork only
   - Match Enterprise security model

2. **Review Routing Configuration Necessity**
   - File: scripts/neo4j-community/cloud-init/standalone.yaml
   - For standalone deployments, full routing/discovery may not be needed
   - Consider if explicit routing address configuration is necessary
   - Enterprise works without explicit routing address configuration

3. **Validate Driver Protocol Usage**
   - Consider if neo4j:// protocol is required for standalone deployments
   - Alternative: Use bolt:// protocol which doesn't require routing
   - Would eliminate need for port 7688 exposure entirely for standalone

4. **Document Port Requirements**
   - Clearly document which ports are required for which deployment modes
   - Standalone vs Cluster should have different port requirements
   - Security vs functionality tradeoffs should be documented

## Best Practice Questions to Research

1. **Neo4j Official Recommendations:**
   - What ports does Neo4j officially recommend exposing to Internet?
   - What is the security guidance for standalone vs cluster deployments?
   - Are there Neo4j security hardening guides to reference?

2. **Driver Compatibility:**
   - Do all Neo4j drivers require routing protocol for standalone?
   - Can bolt:// protocol be used instead for simpler security model?
   - What functionality is lost without routing protocol?

3. **Azure Marketplace Standards:**
   - What are Azure Marketplace security requirements for exposed ports?
   - How do other database offerings handle similar scenarios?
   - Are there Azure security best practices we should follow?

## Related Files to Review

### Network Security Group Rules:
- marketplace/neo4j-enterprise/modules/network.bicep (lines 7-112)
- marketplace/neo4j-community/modules/network.bicep (lines 7-98)

### Cloud-Init Configuration:
- scripts/neo4j-enterprise/cloud-init/standalone.yaml (line 84)
- scripts/neo4j-enterprise/cloud-init/cluster.yaml
- scripts/neo4j-community/cloud-init/standalone.yaml (lines 57-61, 78)

### Cluster-Specific Configuration:
- scripts/neo4j-enterprise/cloud-init/read-replica.yaml (line 69 - uses port 5000 internally)
- Port 5000 used for internal cluster member discovery
- Should NOT be exposed to Internet

## Immediate Action Required

**Before deploying to production or updating Azure Marketplace listings:**

1. Remove or restrict port 5000 in Community edition to match Enterprise
2. Test if routing still works with this restriction
3. Document the final security model in user-facing documentation
4. Consider adding deployment-mode-specific NSG rules (standalone vs cluster)

## Critical Discovery: Main Branch Also Used neo4j:// Protocol

### How Did Main Branch Tests Work?

**Main Branch Test Configuration:**
- File: `.github/workflows/enterprise.yml` (main branch)
- Used external tool: `neo4jtester_linux`
- Constructed URI: `neo4j://hostname:7687` (same as current branch)
- Port 7688 was NOT exposed to Internet
- Routing addresses configured with privateIP

**Current Branch Test Configuration:**
- File: `deployments/src/validate_deploy.py`
- Uses Python driver: `neo4j==5.28.2`
- Constructs URI: `neo4j://hostname:7687` (line 527 in orchestrator.py)
- Port 7688 IS exposed to Internet
- Gets error: "Unable to retrieve routing information" when port not exposed

### Mystery: Why Did Main Branch Tests Pass?

**Three Possible Explanations:**

1. **neo4jtester has different fallback behavior**
   - External Go binary may handle routing failures differently
   - Might automatically fall back to bolt:// when routing fails
   - Python driver may be more strict about routing requirements

2. **Tests were actually failing on main branch**
   - Need to check GitHub Actions history
   - Possibly tests were not catching this error
   - Could explain why routing was broken for users

3. **Driver version differences**
   - neo4jtester uses different Neo4j driver than Python
   - Different driver versions have different routing behavior
   - Newer Python driver (5.28.2) may be stricter

### Validation: Test With bolt:// Protocol

**Quick Test Needed:**
- Modify deployments/src/orchestrator.py line 527
- Change from `neo4j://` to `bolt://`
- Test if validation works without port 7688 exposed
- This would prove whether routing is actually needed

**Files to modify for bolt:// testing:**
- `deployments/src/orchestrator.py` (line 527) - URI construction
- `deployments/src/models.py` (line 218) - Field description
- Update documentation/examples

## Key Decision Required: Port 7688 Internet Exposure

### Main Branch Approach (More Secure, Less Functional)
- Port 7688 NOT exposed to Internet
- neo4j:// protocol does NOT work from external clients
- Users must use bolt:// protocol
- Minimal attack surface

### Current Branch Approach (Less Secure, More Functional)
- Port 7688 exposed to Internet
- neo4j:// protocol works from external clients
- Cluster-aware driver features available
- Increased attack surface

### Recommendation Options

**Option 1: Match Main Branch Security (Remove Port 7688)**
- Remove port 7688 from Internet access in both editions
- Document that users must use bolt:// protocol
- Most secure option
- Loses cluster-aware driver functionality for external clients

**Option 2: Keep Current Approach (Port 7688 Open)**
- Keep port 7688 exposed in both editions
- Document security implications in marketplace listing
- Better driver compatibility
- Slightly increased attack surface

**Option 3: Make It Configurable**
- Add parameter to enable/disable routing port exposure
- Default to closed (secure by default)
- Users can opt-in for routing functionality
- Most flexible but more complex

### Decision Needed Before Marketplace Publication

This is a product decision that impacts:
- Security posture of marketplace offering
- User experience and driver compatibility
- Documentation and support requirements
- Comparison with competitor database offerings

Research needed:
- How do MongoDB, PostgreSQL, MySQL Azure marketplace offerings handle this?
- What does Neo4j AuraDB expose?
- What do Neo4j's official docs recommend?

## Status

- Date Identified: 2025-11-20
- Severity: Medium (Security model changed from main branch)
- Impact: Current branch exposes port 7688, main branch did not
- Community edition fixed to match Enterprise (port 5000 no longer exposed)
- Decision needed: Keep port 7688 open or revert to main branch security model
