# Neo4j Clustering on AKS - Simplified Implementation Proposal

**Status:** Phase 2 Complete
**Version:** 1.0
**Last Updated:** November 20, 2025

## Implementation Status

**IMPORTANT CORRECTION (Nov 20, 2025):**
The initial implementation attempted to use a single Helm installation with `replicas=3`, which does NOT align with Neo4j's official Kubernetes deployment approach. The official neo4j/neo4j Helm chart requires **three separate installations** (one per server) to form a cluster.

**Phase 1: Multi-Installation Architecture** - 🔄 IN PROGRESS (Nov 20, 2025)
- Restructuring Bicep to install Helm chart 3 times (server-1, server-2, server-3)
- Each installation creates 1 StatefulSet with 1 pod
- Servers join cluster via shared `neo4j.name` parameter
- Following official Neo4j Kubernetes Operations Manual guidance

**Phase 2: RBAC and Service Discovery** - ⏳ PENDING
- RBAC configuration for K8S resolver (per-server ServiceAccounts)
- Headless service for cluster member discovery
- K8S resolver configuration for Kubernetes-native discovery

**Phase 3: Validation and Testing** - ⏳ PENDING

---

## IMPORTANT: Follow Official Neo4j Best Practices

This proposal strictly adheres to guidance from:
- **Neo4j Kubernetes Operations Manual:** https://neo4j.com/docs/operations-manual/current/kubernetes/
- **Neo4j Cloud Deployments Guide:** https://neo4j.com/docs/operations-manual/current/cloud-deployments

All implementation decisions align with Neo4j's recommended practices for Kubernetes deployments.

---

## Executive Summary

This proposal outlines a straightforward implementation to enable Neo4j clustering on Azure Kubernetes Service using the existing Bicep and Helm infrastructure. The goal is to create a high-quality demonstration of Neo4j cluster deployment on AKS with minimal complexity.

**Current State:**
- Deployment supports nodeCount parameter (1, 3-10)
- Uses LIST resolver for cluster discovery
- StatefulSet deployment with basic configuration
- Works for standalone instances (nodeCount=1)

**Proposed State:**
- Fully functional Neo4j clusters (3, 5, 7 nodes)
- Kubernetes-native service discovery using K8S resolver
- Headless service for cluster member discovery
- Proper RBAC configuration for service discovery
- Validated cluster formation and basic operations

**Out of Scope:**
- Backup and restore automation
- TLS encryption for cluster communication
- Performance optimization and tuning
- Advanced monitoring and alerting
- Dynamic scaling operations
- Migration from existing deployments

---

## Goals

### Primary Goal

Enable deployment of functional Neo4j clusters on AKS that demonstrate proper cluster formation, quorum management, and basic high availability using Kubernetes-native service discovery.

### Success Criteria

1. **Three-node cluster deploys successfully** - All three members form quorum and reach online state within five minutes
2. **Service discovery works reliably** - Cluster members discover each other using Kubernetes API without manual DNS configuration
3. **Cluster survives pod restarts** - Individual pod restarts do not disrupt cluster operations
4. **Data persists across restarts** - Each cluster member maintains data on dedicated persistent storage
5. **Validation framework confirms functionality** - Automated tests verify cluster formation and basic operations

---

## Requirements

### Functional Requirements

#### FR1: Headless Service for Cluster Discovery

Create a Kubernetes headless service that provides DNS entries for each StatefulSet pod, enabling cluster members to address each other directly.

**Requirements:**
- Service must set clusterIP to None
- Service must include discovery port (6000) with correct naming
- Service selector must match Neo4j cluster pods
- DNS records created for each pod following pattern: podname.servicename.namespace.svc.cluster.local

**Rationale:**
Headless services are required for StatefulSet pod discovery and are a standard Kubernetes pattern for clustered applications.

#### FR2: Kubernetes-Native Service Discovery

Configure Neo4j to use K8S resolver for cluster member discovery through Kubernetes API.

**Requirements:**
- Neo4j configured with resolver type K8S
- Label selector identifies cluster member services
- Service port name matches discovery port configuration
- Each pod advertises its unique DNS name

**Rationale:**
K8S resolver is the most cloud-native approach for Kubernetes deployments, provides immediate topology updates, and requires no external DNS infrastructure.

#### FR3: RBAC Configuration for Service Discovery

Create ServiceAccount, Role, and RoleBinding to grant Neo4j pods permission to query Kubernetes services for discovery.

**Requirements:**
- ServiceAccount created for Neo4j pods
- Role grants minimal permissions (get, list, watch services)
- RoleBinding connects ServiceAccount to Role
- Permissions scoped to namespace only, not cluster-wide

**Rationale:**
K8S resolver requires Kubernetes API access. Minimal RBAC permissions follow security best practices and principle of least privilege.

#### FR4: Persistent Storage Per Cluster Member

Each cluster member must have dedicated persistent storage that survives pod restarts.

**Requirements:**
- StatefulSet volumeClaimTemplate creates PVC per pod
- Storage class uses Azure Premium SSD
- Reclaim policy set to Retain to prevent data deletion
- Volume size configurable via diskSize parameter

**Rationale:**
Database clusters require persistent storage to maintain data across pod lifecycle events. Independent storage per member ensures data isolation.

#### FR5: Cluster Configuration

Neo4j configuration must enable proper cluster formation with appropriate quorum settings.

**Requirements:**
- Minimum cluster size parameter matches node count
- Cluster name configured consistently across members
- Discovery port configured as 6000 (Neo4j 5.x standard)
- Each pod advertises unique address

**Rationale:**
Proper cluster configuration is essential for quorum establishment and cluster stability.

### Non-Functional Requirements

#### NFR1: Simplicity

Implementation must be straightforward and easy to understand for demonstration purposes.

**Requirements:**
- Use standard Kubernetes patterns (StatefulSet, headless service)
- Avoid complex configuration or custom resources
- Clear separation between infrastructure (Bicep) and application (Helm)
- Minimal parameters required for basic deployment

#### NFR2: Reliability

Cluster deployment must succeed consistently across different AKS environments.

**Requirements:**
- Deployment succeeds on AKS versions 1.28 and above
- Works with default AKS networking configurations
- Handles pod restart scenarios gracefully
- Automated validation confirms functionality

---

## Architecture Overview

### Components

**Infrastructure Layer (Bicep):**
- AKS cluster with system and user node pools
- Virtual network and subnets
- Managed identity for workload authentication
- Storage class for Premium SSD
- Log Analytics workspace

**Application Layer (Helm - Per Official Neo4j Approach):**
- **Three separate Helm installations** (server-1, server-2, server-3)
- Each installation creates:
  - 1 StatefulSet with 1 pod (NOT replicas=3 in single installation)
  - 1 headless service for that server
  - 1 ServiceAccount for Kubernetes API access
  - 1 Role and RoleBinding for RBAC
  - ConfigMaps for Neo4j configuration
  - Secrets for credentials
  - 1 PersistentVolumeClaim for data storage
- **One shared LoadBalancer service** for external access to all servers
- Servers join cluster via shared `neo4j.name` parameter

### Service Discovery Architecture

**K8S Resolver Approach:**

Neo4j uses Kubernetes API to query services based on label selectors. The ServiceAccount grants pods permission to list services in their namespace.

**Configuration Pattern:**
- Resolver type: K8S
- Label selector: app=neo4j,component=cluster
- Service port name: discovery
- Advertised address: pod-specific DNS name

**Benefits:**
- No DNS dependencies
- Immediate topology updates
- Cloud-native integration
- Simple to configure and troubleshoot

### Network Architecture

**Headless Service (cluster-internal):**
- Name: neo4j-headless
- ClusterIP: None
- Ports: discovery (6000), bolt (7687), http (7474)
- Enables DNS-based pod addressing

**LoadBalancer Service (external access):**
- Name: neo4j-lb
- Type: LoadBalancer
- Ports: bolt (7687), http (7474)
- Provides external client connectivity

### Storage Architecture

Each cluster member receives dedicated persistent storage:
- Storage class: neo4j-premium (Azure Premium SSD)
- Reclaim policy: Retain
- Volume binding: WaitForFirstConsumer
- Size: Configurable via diskSize parameter (default 32 GB)

---

## Implementation Plan

### Phase 1: Multi-Installation Architecture Setup

**Duration:** 1-2 weeks

**Objective:** Restructure Bicep deployment to install the Neo4j Helm chart three separate times (following official Neo4j Kubernetes Operations Manual), with each installation creating one cluster member that joins via shared cluster name.

#### Requirements

**R1.1: Multiple Helm Installation Support**

Modify Bicep to install the neo4j/neo4j Helm chart **three separate times** instead of once with replicas=3.

Implementation must:
- Create three deployment script resources (or use array/loop)
- Each installation has unique release name (server-1, server-2, server-3)
- All three share the same `neo4j.name` parameter (e.g., "neo4j-cluster")
- Each installation sets `neo4j.minimumClusterSize=3`
- Deployments run sequentially or in parallel (testing needed)

**R1.2: Per-Server Configuration**

Each Helm installation must create independent Kubernetes resources.

Each server gets:
- Unique StatefulSet (e.g., server-1, server-2, server-3) with 1 replica
- Unique headless service for that StatefulSet
- Unique ServiceAccount for K8S resolver permissions
- Unique PersistentVolumeClaim for data storage
- Shared cluster name via `neo4j.name` parameter

**R1.3: Shared Resources**

Create shared resources that all cluster members use.

Shared resources:
- One LoadBalancer service pointing to all three servers
- Shared namespace (neo4j)
- Shared storage class
- Shared configuration (passwords, licenses)

#### Phase 1 Todo List

1. **Remove invalid `replicas` parameter** - Delete the `--set replicas=$NODE_COUNT` line from helm-deployment.bicep as it's not supported by neo4j/neo4j chart

2. **Create helm deployment loop** - Modify Bicep to install Helm chart 3 times using array iteration or separate deployment scripts

3. **Configure unique release names** - Set release names to server-1, server-2, server-3 for each installation

4. **Set shared cluster name** - Ensure all three installations use `--set neo4j.name=neo4j-cluster`

5. **Set minimumClusterSize** - Configure all installations with `--set neo4j.minimumClusterSize=3`

6. **Handle sequential vs parallel** - Determine if installations should run sequentially (safer) or in parallel (faster)

7. **Update output collection** - Modify Bicep outputs to collect information from all three deployments

8. **Test basic deployment** - Verify all three Helm installations complete successfully

9. **Verify cluster formation** - Confirm three separate pods are created and join the cluster

10. **Perform code review and testing** - Review Bicep changes, test 3-node deployment, verify all pods reach running state, validate cluster quorum is formed

---

### Phase 2: Neo4j Cluster Configuration

**Duration:** 1 week

**Objective:** Configure Neo4j to use K8S resolver for cluster discovery and update StatefulSet configuration to support clustering.

#### Requirements

**R2.1: Configure K8S Resolver**

Update Neo4j configuration to use K8S resolver with appropriate settings.

Configuration must:
- Set resolver type to K8S
- Configure label selector to identify cluster services
- Set service port name to "discovery"
- Configure advertised address per pod using pod DNS name

**R2.2: Update StatefulSet Configuration**

Modify StatefulSet to use ServiceAccount and inject pod identity information.

StatefulSet must:
- Reference neo4j-sa ServiceAccount
- Use downward API to inject pod name and namespace
- Configure environment variables for Neo4j with pod-specific values
- Ensure volumeClaimTemplate creates PVC per pod

**R2.3: Configure Cluster Parameters**

Set Neo4j cluster parameters for proper quorum and member configuration.

Parameters must:
- Set minimum cluster size to match node count
- Configure cluster name consistently
- Enable cluster mode when nodeCount >= 3
- Use standalone mode when nodeCount = 1

**R2.4: Add Service Labels**

Update headless service labels to match K8S resolver label selector.

Labels must:
- Include app=neo4j for application identification
- Include component=cluster for cluster member identification
- Include release name for deployment tracking
- Match label selector configured in Neo4j

#### Phase 2 Todo List

1. **Update Neo4j configuration template** - Add K8S resolver configuration to Helm chart values and templates

2. **Configure label selector** - Set dbms.kubernetes.label_selector to match headless service labels

3. **Configure service port name** - Set dbms.kubernetes.discovery.service_port_name to "discovery"

4. **Configure advertised address** - Use environment variable substitution to set pod-specific advertised address

5. **Update StatefulSet ServiceAccount** - Set serviceAccountName in StatefulSet spec to neo4j-sa

6. **Inject pod identity** - Use downward API to expose pod name and namespace as environment variables

7. **Configure minimum cluster size** - Set neo4j.minimumClusterSize Helm parameter to match nodeCount

8. **Update headless service labels** - Add required labels (app, component, release) to headless service metadata

9. **Add cluster mode detection** - Implement logic to determine standalone vs cluster mode based on nodeCount

10. **Test cluster formation** - Deploy three-node cluster and verify all members discover each other and form quorum

11. **Update documentation** - Document K8S resolver configuration and cluster parameters

12. **Perform code review and testing** - Review configuration changes, test three-node cluster deployment, verify cluster forms quorum, validate pod restarts don't break cluster, test standalone mode still works

---

### Phase 3: Validation and Testing

**Duration:** 1 week

**Objective:** Extend validation framework to test cluster functionality and ensure reliable deployments.

#### Requirements

**R3.1: Cluster Formation Validation**

Create automated tests that verify cluster members discover each other and form quorum.

Tests must:
- Deploy cluster with specified node count
- Wait for all pods to reach ready state
- Query cluster status via Cypher (SHOW SERVERS)
- Verify all members are online
- Confirm quorum is established

**R3.2: Data Replication Validation**

Create tests that verify data replicates across cluster members.

Tests must:
- Create test dataset on cluster
- Query dataset from different cluster members
- Verify data is consistent across members
- Confirm read operations work on all members

**R3.3: Pod Restart Validation**

Create tests that verify cluster survives pod restarts.

Tests must:
- Deploy stable cluster
- Delete one pod
- Wait for pod to restart
- Verify pod rejoins cluster
- Confirm cluster operations continue normally

**R3.4: Integration with Deployment Framework**

Integrate cluster tests into existing deployments/ validation framework.

Integration must:
- Add cluster test scenarios to framework
- Use existing validation infrastructure
- Report results consistently with other tests
- Support CI/CD pipeline integration

#### Phase 3 Todo List

1. **Create cluster formation test** - Add test that deploys three-node cluster and validates quorum formation

2. **Create cluster status validation** - Implement Cypher query execution to check SHOW SERVERS output

3. **Create data replication test** - Add test that creates data and verifies it appears on all cluster members

4. **Create pod restart test** - Add test that simulates pod failure and validates cluster recovery

5. **Create five-node cluster test** - Add test scenario for larger cluster deployment

6. **Integrate with deployments framework** - Add cluster test cases to deployments/src/validate_deploy.py

7. **Create test configuration** - Add cluster test scenarios to deployment configuration files

8. **Add test documentation** - Document cluster test scenarios and expected outcomes

9. **Test in CI/CD pipeline** - Verify tests run successfully in GitHub Actions workflow

10. **Perform code review and testing** - Review all test implementations, execute full test suite, verify all tests pass consistently, validate test coverage is adequate, confirm tests catch real issues

---

## Update Plan

This section provides a simple todo list for updating the current deployment to support clustering.

### Update Todo List

1. **Review current Helm chart structure** - Understand existing templates and values to plan integration points for cluster resources

2. **Add headless service template** - Create new template file for headless service with all required ports and labels

3. **Add RBAC templates** - Create template files for ServiceAccount, Role, and RoleBinding with minimal permissions

4. **Update Helm values file** - Add new parameters for cluster configuration (resolver type, label selector, service port name)

5. **Modify Neo4j configuration template** - Update ConfigMap template to include K8S resolver settings when cluster mode enabled

6. **Update StatefulSet template** - Add ServiceAccount reference and downward API for pod identity injection

7. **Update helm-deployment.bicep** - Modify deployment script to pass cluster configuration parameters to Helm chart

8. **Add cluster mode logic** - Implement conditional logic that enables cluster config when nodeCount >= 3

9. **Update parameters.json** - Add test configurations for three-node and five-node clusters

10. **Test standalone deployment** - Verify existing standalone deployments (nodeCount=1) still work correctly

11. **Test three-node cluster** - Deploy three-node cluster and verify successful formation

12. **Test five-node cluster** - Deploy five-node cluster and validate all members join

13. **Add validation tests** - Implement cluster validation tests in deployments/ framework

14. **Update README documentation** - Add cluster deployment instructions and architecture overview

15. **Update troubleshooting guide** - Add common cluster issues and resolution steps

16. **Create deployment examples** - Add example parameter files for different cluster configurations

17. **Test across AKS versions** - Validate deployment works on AKS 1.28, 1.29, 1.30, 1.31

18. **Verify pod distribution** - Confirm pods distribute across AKS nodes appropriately

19. **Test pod restart scenarios** - Validate cluster survives individual pod restarts

20. **Perform comprehensive code review and testing** - Final review of all changes, execute complete test suite, validate documentation accuracy, confirm all acceptance criteria met

---

## Success Metrics

### Deployment Success
- Three-node cluster deploys successfully in under five minutes
- All cluster members reach online state
- Quorum is established without manual intervention

### Functionality Success
- Data written to cluster is readable from all members
- Individual pod restarts do not disrupt cluster operations
- Cluster status query (SHOW SERVERS) shows all members online

### Validation Success
- All automated tests pass consistently
- Tests execute successfully in CI/CD pipeline
- Test coverage includes standalone and cluster scenarios

---

## Risks and Mitigations

### Risk 1: RBAC Configuration Issues

**Risk:** Incorrect RBAC permissions prevent pods from discovering services.

**Mitigation:**
- Use kubectl auth can-i to validate permissions before deployment
- Include RBAC validation in automated tests
- Provide clear error messages when permissions are missing

### Risk 2: Cluster Formation Failures

**Risk:** Cluster members fail to discover each other or form quorum.

**Mitigation:**
- Implement detailed logging of discovery process
- Add validation that headless service is ready before pods start
- Include troubleshooting steps in documentation

### Risk 3: Configuration Complexity

**Risk:** Cluster configuration is too complex for users to understand and modify.

**Mitigation:**
- Use sensible defaults that work for common scenarios
- Minimize required parameters
- Provide clear examples and documentation

---

## Documentation Requirements

### Technical Documentation

**Cluster Architecture:**
- Overview of cluster components
- Service discovery mechanism explanation
- Network architecture with port mappings
- Storage architecture per cluster member

**Configuration Reference:**
- All Bicep parameters with descriptions
- All Helm values with valid options
- Neo4j cluster configuration parameters
- RBAC permissions explanation

### Operational Documentation

**Deployment Procedures:**
- How to deploy standalone instance
- How to deploy three-node cluster
- How to deploy five-node cluster
- Parameter customization guide

**Troubleshooting Guide:**
- Cluster formation issues
- RBAC permission errors
- Service discovery problems
- Common configuration mistakes

### Example Configurations

**Parameter Files:**
- standalone.json (nodeCount=1)
- cluster-3node.json (nodeCount=3)
- cluster-5node.json (nodeCount=5)

---

## Timeline

**Total Duration:** 3 weeks

- **Week 1:** Phase 1 - Headless Service and RBAC Setup
- **Week 2:** Phase 2 - Neo4j Cluster Configuration
- **Week 3:** Phase 3 - Validation and Testing

**Deliverables:**
- Updated Bicep templates supporting cluster deployment
- Updated Helm chart with cluster resources
- Validation tests for cluster functionality
- Comprehensive documentation

---

## Conclusion

This simplified proposal provides a straightforward path to enable Neo4j clustering on AKS. By focusing on core essentials and using Kubernetes-native patterns, the implementation remains simple while delivering a high-quality demonstration of Neo4j cluster capabilities.

The phased approach ensures each component is validated before building upon it, minimizing risk and enabling rapid troubleshooting if issues arise.

**Key Principles:**
- Simplicity over complexity
- Standard Kubernetes patterns
- Minimal configuration required
- Automated validation
- Clear documentation

**Success Criteria:**
- Three-node cluster deploys reliably
- Cluster forms quorum automatically
- Tests validate functionality
- Documentation enables understanding

---

**Next Steps:**
1. Stakeholder review and approval
2. Test environment setup
3. Phase 1 implementation
4. Iterative testing and refinement
5. Documentation completion

---

**Document Version:** 1.0
**Last Updated:** November 20, 2025
