# Incremental Cloud-Init Native Migration

**Date:** 2025-11-16
**Status:** Proposed
**Approach:** Incremental, risk-minimized migration from bash scripts to cloud-init native

---

## Executive Summary

This proposal outlines a **6-phase incremental approach** to migrating Neo4j deployment from bash scripts to cloud-init native modules. Each phase is **independently deployable and testable**, allowing us to validate functionality before proceeding to the next phase.

### Why Incremental?

**Benefits:**
- Lower risk - validate each phase before proceeding
- Faster time to working deployment - get value after each phase
- Easier debugging - isolate issues to specific functionality
- Flexibility - can pause/adjust based on learnings
- Team learning - build cloud-init expertise incrementally

**Trade-offs:**
- Longer total timeline (but faster to first working deployment)
- Temporary hybrid state (cloud-init + embedded bash)
- More commits/releases

### Success Criteria for Each Phase

Each phase must meet these criteria before proceeding:
1. Deployment succeeds for all test scenarios
2. Neo4j validates successfully (using validate_deploy)
3. Functionality matches previous phase exactly
4. No regressions in deployment time or reliability
5. Documentation updated
6. Code reviewed

---

## Phase Breakdown

### Phase 3.0: Foundation - Embed Bash in Cloud-Init (Week 1)

**Objective:** Eliminate external script URLs while maintaining exact current functionality

**Approach:**
- Create cloud-init YAML files that embed the existing bash scripts
- Use cloud-init `write_files` to write bash scripts to VM filesystem
- Use cloud-init `runcmd` to execute the embedded bash scripts
- Pass all parameters from Bicep template to bash scripts via cloud-init
- Embed cloud-init YAML in Bicep template using `loadTextContent()`

**What Gets Migrated:**
- Nothing changes in bash scripts themselves
- Scripts move from external GitHub URLs to embedded in cloud-init
- VM customData uses cloud-init instead of CustomScript extension

**What Stays the Same:**
- All bash script logic unchanged
- All parameters unchanged
- All deployment configurations work identically

**Testing Requirements:**
- Deploy standalone Neo4j 5.x - verify identical to bash script deployment
- Deploy 3-node cluster - verify cluster forms correctly
- Deploy with GDS plugin - verify plugin installs
- Deploy Neo4j 4.4 - verify correct version
- Compare deployment logs with bash script logs

**Deliverables:**
1. cloud-init-neo4j5.yaml with embedded node.sh
2. cloud-init-neo4j44.yaml with embedded node4.sh
3. cloud-init-readreplica44.yaml with embedded readreplica4.sh
4. Updated mainTemplate.bicep using customData with cloud-init
5. Removed scriptsBaseUrl variable and script URL references
6. Updated deploy.sh to work with cloud-init
7. Documentation of cloud-init embedding approach

**Success Metrics:**
- Zero deployment failures
- Deployment time within 10% of bash script approach
- All validate_deploy tests pass

**Risk Mitigation:**
- Keep bash scripts unchanged - lowest risk
- Can roll back to external scripts if issues arise
- Extensive testing before proceeding to Phase 3.1

---

### Phase 3.1: Infrastructure Native - Disk and System Setup (Week 2)

**Objective:** Migrate disk mounting and system configuration to cloud-init native modules

**Scope:**
Replace bash script sections for:
- Disk formatting and mounting
- Firewall configuration
- System package installation
- Basic system configuration

**Current Bash Functionality:**
- mount_data_disk() function
- Disk partitioning with parted
- XFS filesystem creation
- UUID-based fstab entries
- systemctl daemon-reload
- firewalld disable

**Cloud-Init Native Approach:**
- Use `disk_setup` module for partitioning
- Use `fs_setup` module for filesystem creation
- Use `mounts` module for persistent mounting
- Use `bootcmd` for early boot operations
- Use `runcmd` only for operations without native modules

**What Gets Migrated:**
- Disk operations move to disk_setup, fs_setup, mounts
- Firewall operations move to runcmd (minimal bash)
- System package installation moves to packages module

**What Stays in Bash:**
- Neo4j installation
- Neo4j configuration
- Cluster operations
- Plugin installation

**Testing Requirements:**
- Verify data disk mounts correctly at /var/lib/neo4j
- Verify disk survives VM restart
- Verify permissions on mount point correct
- Verify firewall disabled
- Compare disk setup with bash script approach

**Deliverables:**
1. Updated cloud-init YAML with native disk_setup/fs_setup
2. Reduced bash script (disk operations removed)
3. Test results showing identical disk configuration
4. Documentation of disk setup approach

**Success Metrics:**
- Disk operations work reliably across all VM sizes
- No manual intervention needed for disk issues
- Deployment time unchanged or faster

**Rollback Plan:**
- If disk operations fail, revert to embedded bash for disk operations
- Keep cloud-init structure but use bash for disk mounting

---

### Phase 3.2: Package Management Native - Neo4j Installation (Week 3)

**Objective:** Migrate Neo4j package installation to cloud-init native modules

**Scope:**
Replace bash script sections for:
- Yum repository configuration
- GPG key import
- Neo4j package installation
- APOC plugin installation
- Service enablement

**Current Bash Functionality:**
- install_neo4j_from_yum() function
- Yum repository file creation
- NEO4J_ACCEPT_LICENSE_AGREEMENT environment variable
- Version detection from versions.neo4j-templates.com
- Plugin file movement

**Cloud-Init Native Approach:**
- Use `yum_repos` module for repository configuration
- Use `runcmd` for GPG key import (no native module)
- Use `packages` module for Neo4j installation
- Use `write_files` for plugin configuration
- Use environment variables in runcmd for license acceptance

**What Gets Migrated:**
- Repository setup moves to yum_repos
- Package installation moves to packages
- Plugin installation to runcmd (simplified)

**What Stays in Bash:**
- Version detection logic (requires API call)
- Complex plugin installation (GDS, Bloom)
- Neo4j configuration
- Cluster operations

**Testing Requirements:**
- Verify correct Neo4j version installed
- Verify APOC plugin installed and loadable
- Verify service enabled and can start
- Test both Enterprise and Evaluation licenses
- Verify version detection works correctly

**Deliverables:**
1. Updated cloud-init with yum_repos and packages modules
2. Further reduced bash script
3. Test matrix for all Neo4j versions and licenses
4. Documentation of package installation approach

**Success Metrics:**
- Neo4j installs reliably
- Correct version selection works
- License acceptance works for both Enterprise and Evaluation
- Plugin installation succeeds

**Dependencies:**
- Requires Phase 3.1 complete (disk must be mounted for plugins)

---

### Phase 3.3: Configuration Native - Neo4j Settings (Week 4)

**Objective:** Migrate Neo4j configuration file generation to cloud-init native modules

**Scope:**
Replace bash script sections for:
- neo4j.conf file generation
- Password setting
- Memory configuration
- Network configuration
- Connector configuration

**Current Bash Functionality:**
- build_neo4j_conf_file() function
- Template-based neo4j.conf generation
- dbms.memory.* settings calculation based on VM size
- Network binding configuration
- Bolt/HTTP/HTTPS connector setup
- Initial password setting

**Cloud-Init Native Approach:**
- Use `write_files` module for neo4j.conf
- Use template variables in cloud-init for dynamic values
- Use Bicep to calculate memory settings and pass to cloud-init
- Use runcmd for password setting (requires neo4j-admin)

**What Gets Migrated:**
- Static configuration to write_files
- Dynamic configuration using cloud-init variables
- Configuration file placement

**What Stays in Bash:**
- Password setting (requires neo4j-admin command)
- Cluster-specific configuration
- Plugin configuration

**Testing Requirements:**
- Verify neo4j.conf generated correctly
- Verify memory settings match VM size
- Verify network bindings correct
- Verify connectors accessible
- Test password setting works

**Deliverables:**
1. Cloud-init write_files for neo4j.conf
2. Bicep template variables for memory calculation
3. Minimal bash for password operations
4. Test suite for configuration generation
5. Documentation of configuration approach

**Success Metrics:**
- Configuration matches bash script output exactly
- Neo4j starts successfully with generated config
- All connectors accessible
- Password authentication works

**Dependencies:**
- Requires Phase 3.2 complete (Neo4j must be installed)

---

### Phase 3.4: Cluster Native - Discovery and Formation (Week 5-6)

**Objective:** Migrate cluster discovery and formation to cloud-init with minimal bash

**Scope:**
Replace or simplify bash script sections for:
- Cluster member discovery via DNS or Azure APIs
- Cluster initialization
- Member joining
- Initial database setup
- Cluster health verification

**Current Bash Functionality:**
- get_cluster_members() function using Azure CLI
- DNS-based discovery using internal Azure DNS
- Primary node detection
- Cluster initialization on first node
- Member joining on additional nodes
- Database creation

**Cloud-Init Approach:**
- Use DNS-based discovery (no Azure CLI needed)
- Use systemd service for cluster join (retries automatically)
- Use cloud-init runcmd for initial cluster bootstrap only
- Leverage Neo4j's built-in cluster formation
- Minimize custom orchestration logic

**What Gets Migrated:**
- DNS lookup logic to simplified cloud-init runcmd
- Service files for cluster operations to write_files
- Cluster configuration to write_files (neo4j.conf)

**What Stays in Bash (Minimal):**
- Cluster initialization command (one-time operation)
- Database creation command (one-time operation)
- Health check command (verification only)

**Testing Requirements:**
- Deploy 3-node cluster - verify all join
- Deploy 5-node cluster - verify formation
- Test cluster resilience (restart nodes)
- Verify database accessible from all nodes
- Verify cluster topology correct
- Test DNS discovery works
- Test load balancer integration

**Deliverables:**
1. Cloud-init with DNS-based discovery
2. Systemd service files for cluster operations
3. Minimal bash for cluster commands
4. Test suite for cluster scenarios
5. Documentation of cluster formation process
6. Troubleshooting guide for cluster issues

**Success Metrics:**
- Cluster forms reliably (95%+ success rate)
- Cluster formation time comparable to bash approach
- No manual intervention needed
- Cluster survives node restarts

**Dependencies:**
- Requires Phase 3.3 complete (configuration must be correct)
- Most complex phase - may need 2 weeks

---

### Phase 3.5: Plugins Native - GDS and Bloom (Week 7)

**Objective:** Migrate plugin installation to cloud-init native approach

**Scope:**
Replace bash script sections for:
- Graph Data Science (GDS) plugin installation
- Neo4j Bloom installation
- License key configuration
- Plugin verification

**Current Bash Functionality:**
- install_graph_data_science() function
- install_bloom() function
- Plugin download from Neo4j distribution site
- License key file placement
- Plugin JAR placement in plugins directory
- Configuration updates for plugins

**Cloud-Init Approach:**
- Use runcmd for plugin download (requires curl/wget)
- Use write_files for license key files
- Use write_files for plugin configuration additions
- Leverage Neo4j's plugin loading mechanism

**What Gets Migrated:**
- License file creation to write_files
- Plugin configuration to write_files
- Download and placement to simplified runcmd

**What Stays in Bash (Minimal):**
- Plugin download logic (requires version matching)
- Plugin verification (requires Neo4j commands)

**Testing Requirements:**
- Deploy with GDS plugin - verify installation
- Deploy with Bloom plugin - verify accessibility
- Deploy with both plugins - verify coexistence
- Verify license keys respected
- Test plugin version compatibility
- Verify plugins load at Neo4j startup

**Deliverables:**
1. Cloud-init plugin installation logic
2. License file templates
3. Plugin configuration templates
4. Test suite for plugin scenarios
5. Documentation of plugin installation

**Success Metrics:**
- Plugins install reliably
- License validation works
- Plugin versions compatible with Neo4j version
- Plugins accessible after deployment

**Dependencies:**
- Requires Phase 3.3 complete (configuration must support plugins)

---

### Phase 3.6: Read Replicas Native - Replica Configuration (Week 8)

**Objective:** Migrate read replica setup to cloud-init native approach

**Scope:**
Replace readreplica4.sh bash script for:
- Read replica discovery of cluster
- Read replica Neo4j configuration
- Read replica plugin installation
- Read replica service startup

**Current Bash Functionality:**
- readreplica4.sh script
- Cluster discovery from replica node
- Replica-specific neo4j.conf settings
- Plugin installation on replicas
- Service configuration for read-only mode

**Cloud-Init Approach:**
- Separate cloud-init YAML for read replicas
- Use DNS discovery to find cluster members
- Use write_files for replica-specific configuration
- Share plugin installation logic from Phase 3.5

**What Gets Migrated:**
- Discovery logic to cloud-init runcmd
- Configuration to write_files
- Plugin installation reused from Phase 3.5

**What Stays in Bash (Minimal):**
- Cluster connection verification
- Replica health check

**Testing Requirements:**
- Deploy cluster with 1 read replica - verify
- Deploy cluster with 3 read replicas - verify
- Verify replicas connect to cluster
- Verify read queries work on replicas
- Verify replicas sync data
- Test replica failover behavior

**Deliverables:**
1. cloud-init-readreplica.yaml
2. Replica-specific configuration templates
3. Test suite for replica scenarios
4. Documentation of replica setup
5. Troubleshooting guide

**Success Metrics:**
- Read replicas deploy reliably
- Replicas connect to cluster automatically
- Read operations work correctly
- Replica lag acceptable

**Dependencies:**
- Requires Phase 3.4 complete (cluster must form correctly)
- Requires Phase 3.5 complete (plugins must work)

---

## Migration Strategy

### Parallel Track Approach

To minimize risk and maximize flexibility:

**Track A: Incremental Cloud-Init (Main)**
- Follow Phase 3.0 → 3.1 → 3.2 → 3.3 → 3.4 → 3.5 → 3.6
- Each phase independently deployable
- Extensive testing at each phase
- Production deployments use latest completed phase

**Track B: Bash Baseline (Fallback)**
- Keep Phase 3.0 (embedded bash) as fallback
- If cloud-init native issues arise, rollback to Phase 3.0
- Maintain until Phase 3.6 complete and validated

### Phase Transition Criteria

Before moving to next phase:
1. **All tests pass** - 100% success rate over 10 test deployments
2. **Performance acceptable** - Deployment time within 10% of baseline
3. **Documentation complete** - Troubleshooting guide updated
4. **Code reviewed** - Peer review completed
5. **User acceptance** - Deployment validated by QA

### Testing Strategy Per Phase

Each phase follows this testing pattern:

1. **Unit Testing** - Individual cloud-init modules work
2. **Integration Testing** - Modules work together
3. **Regression Testing** - Previous phases still work
4. **Deployment Testing** - Full deployment succeeds
5. **Validation Testing** - validate_deploy passes
6. **Performance Testing** - Deployment time comparable
7. **Stress Testing** - Multiple concurrent deployments

### Rollback Strategy

If a phase fails:

1. **Immediate rollback** - Revert to previous phase
2. **Root cause analysis** - Understand failure
3. **Fix approach** - Adjust implementation
4. **Retry** - Test again before proceeding

Each phase is tagged in git for easy rollback:
- `phase-3.0-embedded-bash`
- `phase-3.1-infra-native`
- `phase-3.2-package-native`
- etc.

---

## Timeline and Resource Allocation

### Estimated Timeline

| Phase | Duration | Cumulative |
|-------|----------|------------|
| Phase 3.0: Embedded Bash | 1 week | 1 week |
| Phase 3.1: Infrastructure | 1 week | 2 weeks |
| Phase 3.2: Package Management | 1 week | 3 weeks |
| Phase 3.3: Configuration | 1 week | 4 weeks |
| Phase 3.4: Cluster Formation | 2 weeks | 6 weeks |
| Phase 3.5: Plugin Installation | 1 week | 7 weeks |
| Phase 3.6: Read Replicas | 1 week | 8 weeks |
| **Total** | **8 weeks** | - |

### Critical Path

**Must complete in order:**
- Phase 3.0 → 3.1 → 3.2 → 3.3 → 3.4
- Phase 3.5 can run parallel to 3.4 (plugins independent)
- Phase 3.6 requires 3.4 + 3.5 complete

### Risk-Adjusted Timeline

**Conservative estimate:** 10 weeks
- Allows 2 weeks buffer for:
  - Unexpected issues in cluster formation (Phase 3.4)
  - Azure platform changes
  - Testing iterations
  - Bug fixes

---

## Success Metrics (Overall)

### Functional Metrics

1. **Deployment Success Rate**
   - Target: 98%+ success rate
   - Measure: Successful deployments / total attempts

2. **Deployment Time**
   - Target: ≤ 10 minutes for standalone
   - Target: ≤ 15 minutes for 3-node cluster
   - Measure: Time from deployment start to Neo4j accessible

3. **Validation Pass Rate**
   - Target: 100% validate_deploy pass rate
   - Measure: Successful validations / total deployments

### Technical Metrics

1. **Cloud-Init Native Percentage**
   - Phase 3.0: 0% native (100% embedded bash)
   - Phase 3.1: 20% native (disk operations)
   - Phase 3.2: 40% native (+ package management)
   - Phase 3.3: 60% native (+ configuration)
   - Phase 3.4: 80% native (+ cluster)
   - Phase 3.5: 90% native (+ plugins)
   - Phase 3.6: 95% native (final state)

2. **Lines of Bash Remaining**
   - Start: 665 lines
   - Phase 3.0: 665 lines (embedded)
   - Phase 3.1: ~550 lines
   - Phase 3.2: ~400 lines
   - Phase 3.3: ~250 lines
   - Phase 3.4: ~100 lines
   - Phase 3.5: ~50 lines
   - Phase 3.6: ~25 lines (minimal)

### Quality Metrics

1. **Code Review Coverage**
   - Target: 100% of cloud-init YAML reviewed
   - Measure: Reviewed files / total files

2. **Documentation Completeness**
   - Target: Each phase fully documented
   - Measure: Troubleshooting guide coverage

3. **Test Coverage**
   - Target: All deployment scenarios tested
   - Measure: Test scenarios passed / total scenarios

---

## Risk Assessment

### High-Risk Phases

**Phase 3.4: Cluster Formation** - Highest complexity
- Risk: Cluster may not form reliably
- Mitigation: Extensive DNS testing, systemd retry logic
- Fallback: Keep bash cluster logic in Phase 3.0

**Phase 3.6: Read Replicas** - Azure-specific
- Risk: Replica discovery may fail
- Mitigation: Test with various cluster sizes
- Fallback: Keep readreplica4.sh embedded

### Medium-Risk Phases

**Phase 3.2: Package Management**
- Risk: Version detection API may be unreliable
- Mitigation: Cache version, have fallback version
- Fallback: Embed version detection in bash

**Phase 3.3: Configuration**
- Risk: Configuration template errors
- Mitigation: Extensive validation, compare with bash output
- Fallback: Keep bash configuration generation

### Low-Risk Phases

**Phase 3.0: Embedded Bash** - Minimal risk
- No logic changes, just embedding location

**Phase 3.1: Infrastructure** - Well-supported
- Cloud-init disk modules are mature and reliable

**Phase 3.5: Plugins** - Independent
- Plugin failures don't prevent Neo4j from working

---

## Recommendations

### Recommended Approach

1. **Start with Phase 3.0** - Get deployments working immediately
2. **Validate Phase 3.0 thoroughly** - This is our baseline
3. **Proceed incrementally** - Complete Phase 3.1, validate, then 3.2, etc.
4. **Don't skip phases** - Each builds on previous
5. **Extensive testing** - Better to catch issues early

### Alternative Approaches Considered

**Alternative 1: Big Bang Migration**
- Convert all bash to cloud-init at once
- **Rejected:** Too risky, hard to debug failures

**Alternative 2: Two-Track (Cloud-Init + Bash)**
- Maintain both bash scripts and cloud-init indefinitely
- **Rejected:** Maintenance burden, technical debt

**Alternative 3: Skip to Phase 3.6**
- Only do Phase 3.0 and 3.6, skip intermediate phases
- **Rejected:** Miss learning and validation benefits

### When to Pause

Consider pausing incremental migration if:
1. Deployment success rate drops below 90%
2. Critical bugs found in cloud-init approach
3. Azure platform changes affect cloud-init
4. Team capacity constraints
5. Higher priority work emerges

Pause is safe because Phase 3.0 provides working baseline.

---

## Documentation Requirements

### Per-Phase Documentation

Each phase must deliver:

1. **Implementation Guide**
   - What changed from previous phase
   - How to deploy this phase
   - How to verify it works

2. **Troubleshooting Guide**
   - Common failure modes
   - How to debug issues
   - How to access cloud-init logs

3. **Rollback Guide**
   - How to revert to previous phase
   - What data/state is lost
   - How to verify rollback successful

### Overall Documentation

After Phase 3.6 complete:

1. **Cloud-Init Architecture Document**
   - Overall design and approach
   - Module usage and rationale
   - Integration with Bicep

2. **Migration History Document**
   - What changed in each phase
   - Lessons learned
   - Performance comparisons

3. **Operations Guide**
   - How to deploy cloud-init templates
   - How to debug deployment issues
   - How to customize for different scenarios

---

## Appendix: Cloud-Init Module Reference

### Modules Used by Phase

**Phase 3.1:**
- `disk_setup` - Partition configuration
- `fs_setup` - Filesystem creation
- `mounts` - Persistent mount points
- `bootcmd` - Early boot commands

**Phase 3.2:**
- `yum_repos` - YUM repository configuration
- `packages` - Package installation
- `runcmd` - Post-install commands

**Phase 3.3:**
- `write_files` - File creation
- `runcmd` - Configuration commands

**Phase 3.4:**
- `write_files` - Service files
- `runcmd` - Cluster commands

**Phase 3.5:**
- `write_files` - License files
- `runcmd` - Plugin installation

**Phase 3.6:**
- `write_files` - Replica configuration
- `runcmd` - Replica setup

### Cloud-Init Execution Order

Understanding cloud-init execution order is critical:

1. `bootcmd` - Very early boot (before networking)
2. `disk_setup` - Disk partitioning
3. `fs_setup` - Filesystem creation
4. `mounts` - Mount filesystems
5. `write_files` - Create files
6. `yum_repos` - Configure repositories
7. `packages` - Install packages
8. `runcmd` - Run commands (after everything else)

This order determines how we structure our migration phases.

---

## Conclusion

The incremental cloud-init migration provides a **pragmatic, low-risk path** to modernizing Neo4j Azure deployments. By breaking the work into small, independently testable phases, we:

- **Reduce risk** through gradual migration
- **Deliver value faster** with working deployments after Phase 3.0
- **Build expertise** in cloud-init incrementally
- **Maintain flexibility** to adjust approach based on learnings
- **Enable rollback** at any point without losing functionality

**Recommended next step:** Begin Phase 3.0 implementation to get deployments working, then evaluate learnings before committing to full native migration.

---

**Last Updated:** 2025-11-16
**Status:** Proposal - Ready for Review
**Next Action:** Approve approach and begin Phase 3.0 implementation
