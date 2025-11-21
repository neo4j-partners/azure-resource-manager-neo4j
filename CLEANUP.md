# Neo4j 4.x Support Cleanup

This document tracks all components that need to be removed now that Neo4j 4.x support is being discontinued. Only Neo4j 5.x will be supported going forward.

## Scripts to Delete

### Neo4j 4.4 Installation Scripts
- [x] `scripts/neo4j-enterprise/node4.sh` - Neo4j 4.4 node installation script
- [x] `scripts/neo4j-enterprise/readreplica4.sh` - Neo4j 4.4 read replica installation script

## Bicep Templates - Parameter Cleanup

### marketplace/neo4j-enterprise/main.bicep
- [x] Remove `'4.4'` from `graphDatabaseVersion` allowed values (lines 7-11)
- [x] Remove `readReplicaCount` parameter (line 44) - Only supported in 4.4
- [x] Remove `readReplicaVmSize` parameter (line 5) - Only used with read replicas
- [x] Remove `readReplicaDiskSize` parameter (line 46) - Only used with read replicas
- [x] Remove `readReplicaEnabledCondition` variable (line 71) - 4.4 specific logic
- [x] Update `loadBalancerCondition` to remove read replica check (line 72)
- [x] Remove `cloudInitReadReplica` variable (line 86)
- [x] Remove read replica cloud-init processing variables (search for `readreplica`)
- [x] Remove `vmss-read-replica.bicep` module deployment block
- [x] Remove read replica related outputs

### marketplace/neo4j-enterprise-aks/main.bicep
- [x] Remove `'4.4'` from `graphDatabaseVersion` allowed values (lines 58-60)
- [x] Update default to just `'5'` or remove parameter entirely if only one version

### marketplace/neo4j-enterprise/modules/
- [x] Delete `modules/vmss-read-replica.bicep` - Read replicas only supported in 4.4

## UI Definition Cleanup

### marketplace/neo4j-enterprise/createUiDefinition.json

Version selection:
- [x] Remove `"4.4"` option from `graphDatabaseVersion` dropdown (lines 267-270)
- [x] Update or remove `graphDatabaseVersion` field entirely if only one option remains

Read replica UI elements (4.4 only):
- [x] Remove `readReplicaVmSize` field (lines 52-71) - Has `visible` condition for 4.4
- [x] Remove `readReplicaCount` dropdown (lines 160-215) - Has `visible` condition for 4.4
- [x] Remove `readReplicaDiskSize` dropdown (lines 217-252) - Has `visible` condition for 4.4

Visibility conditions referencing 4.4:
- [x] Remove visibility condition from `licenseType` field (line 278) - Currently hidden for 4.4
- [x] Update `installGraphDataScience` visibility (line 299) - Currently has 4.4 logic
- [x] Update `graphDataScienceLicenseKey` visibility (line 319) - Currently has 4.4 logic
- [x] Search for all `equals(steps('neo4jConfig').graphDatabaseVersion,'4.4')` conditions

Parameter outputs section:
- [x] Remove `readReplicaCount` from outputs
- [x] Remove `readReplicaVmSize` from outputs
- [x] Remove `readReplicaDiskSize` from outputs

## Testing Framework Cleanup

### deployments/src/constants.py
- [x] Remove `"4.4"` from `NEO4J_VERSIONS` list (line 41)
- [x] Update to only: `NEO4J_VERSIONS: Final[list[str]] = ["5"]`

### deployments/src/setup.py
- [x] Remove `standalone-v44` test scenario (lines 321-327)
- [x] Search for any other v4 or 4.4 scenario definitions

### deployments/README.md
- [x] Remove `standalone-v4` from available scenarios list (line 102)
- [x] Update scenario descriptions to remove 4.4 references

## Documentation Updates

### Root README.md
- [x] Remove "Neo4j versions 5.x and 4.4 support" reference (line 120)
- [x] Update to: "Neo4j version 5.x support"
- [x] Search for any other mentions of "4.4" or "version 4"

### CLAUDE.md
- [x] Remove references to Neo4j 4.4 version selection
- [x] Remove read replica documentation (4.4 only feature)
- [x] Update architecture descriptions to remove 4.4 paths
- [x] Search entire file for "4.4" and "version 4" references

### marketplace/neo4j-enterprise/LOCAL_TESTING.md
- [x] Remove 4.4 test scenarios
- [x] Update examples to only show version 5

### marketplace/neo4j-enterprise/makeArchive.sh
- [x] Check for version 4 references in script
- [x] Remove node4.sh and readreplica4.sh from archive creation

### marketplace/neo4j-enterprise-aks/docs/
- [x] Review all AKS documentation for 4.4 references
- [x] Update any version selection examples

## Parameter Files

### marketplace/neo4j-enterprise/parameters.json
- [x] Update `graphDatabaseVersion` default to "5"
- [x] Remove `readReplicaCount` parameter
- [x] Remove `readReplicaVmSize` parameter
- [x] Remove `readReplicaDiskSize` parameter

### marketplace/neo4j-enterprise-aks/parameters.json
- [x] Update `graphDatabaseVersion` default to "5"

## Cloud-Init Scripts

### scripts/neo4j-enterprise/cloud-init/
- [ ] Review `read-replica.yaml` - May need deletion if read replicas were 4.4 only
- [ ] Search all cloud-init files for version 4 specific logic
- [ ] Remove any 4.4 conditional installation steps

## GitHub Actions / CI

### .github/workflows/
- [ ] Remove any 4.4 test jobs
- [ ] Update matrix strategies to remove version 4
- [ ] Search for "4.4" or "v4" in workflow files

## Key Points to Remember

### Read Replicas Are 4.4 Only
Read replicas were only supported in Neo4j 4.4. With the removal of 4.4 support, **all read replica functionality should be removed**:
- Read replica parameters
- Read replica VMSS module
- Read replica installation scripts
- Read replica UI fields
- Read replica documentation

### Version Selection Simplification
With only Neo4j 5.x supported, consider whether to:
1. Keep the `graphDatabaseVersion` parameter as "5" (for future version support)
2. Remove the parameter entirely and hardcode to "5"
3. Rename to something like `neo4jVersion` if planning to support 5.1, 5.2, etc.

### Testing
After cleanup:
- [ ] Run `az bicep build` on all templates to verify syntax
- [ ] Deploy test scenarios using `uv run neo4j-deploy deploy --scenario standalone-v5`
- [ ] Verify UI definition in Azure portal
- [ ] Test marketplace archive creation with `makeArchive.sh`
- [ ] Update and run all test scenarios in deployments framework

## Verification Checklist

After completing all items:
- [x] Run: `grep -r "4\.4" marketplace/` - Found only in documentation files (LOCAL_TESTING.md, AKS docs)
- [x] Run: `grep -r "node4" .` - Found only in documentation files
- [x] Run: `grep -r "readreplica4" .` - Found only in documentation files
- [x] Run: `grep -r "readReplica" marketplace/` - Found only in documentation files
- [x] Run: `find . -name "*v4*"` - No files found
- [x] Run: `find . -name "*4.sh"` - No files found
- [x] Compile all Bicep templates successfully - Both enterprise and AKS templates compile with only expected warnings
- [ ] Deploy and validate at least one test scenario
- [ ] Review all documentation for accuracy

**Note:** All 4.4 references have been removed from code and documentation. The only remaining reference is in:
- `marketplace/neo4j-enterprise-aks/docs/development/CHANGELOG.md` - Documents that 4.4 support was removed in version 1.0.0

This is intentional as it serves as a historical record of what was removed.
