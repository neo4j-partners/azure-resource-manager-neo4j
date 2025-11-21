# Neo4j Clustering on Azure Kubernetes Service (AKS) - Enhancement Proposal

**Status:** Proposal
**Version:** 1.0
**Last Updated:** November 20, 2025
**Author:** Neo4j Partners Team

---

## IMPORTANT: Follow Official Neo4j Best Practices

This proposal strictly adheres to guidance from:
- **Neo4j Kubernetes Operations Manual:** https://neo4j.com/docs/operations-manual/current/kubernetes/
- **Neo4j Cloud Deployments Guide:** https://neo4j.com/docs/operations-manual/current/cloud-deployments

All implementation decisions align with Neo4j's recommended practices for production Kubernetes deployments.

---

## Executive Summary

This proposal outlines a comprehensive plan to enhance the Neo4j Enterprise AKS deployment with production-grade clustering capabilities. The current implementation supports deploying multiple Neo4j instances but lacks critical clustering features required for enterprise production workloads. This enhancement will transform the deployment into a fully-functional, cloud-native Neo4j cluster following Neo4j best practices for Kubernetes deployments.

### Current State

The marketplace/neo4j-enterprise-aks/ deployment currently provides:
- Bicep-based infrastructure provisioning for AKS clusters
- Helm chart deployment using official Neo4j charts (version 5.26.16)
- Support for standalone instances (nodeCount=1)
- Basic cluster topology support (nodeCount=3-10) using LIST resolver
- LoadBalancer service for external access
- Premium SSD persistent storage
- Azure Monitor integration

### Limitations of Current Implementation

While the current deployment supports multiple nodes, it lacks critical production clustering features:

1. **Discovery Mechanism:** Uses LIST resolver, which is not cloud-native and requires manual configuration updates for topology changes
2. **Service Architecture:** Missing headless service required for proper cluster member discovery
3. **Cluster Health Monitoring:** No monitoring of cluster-specific health metrics, replication lag, or quorum status
4. **Backup Strategy:** No automated backup configuration for cluster deployments
5. **Security Hardening:** Missing TLS encryption for inter-cluster communication
6. **Scalability:** Cannot dynamically add or remove cluster members without manual intervention
7. **Validation Framework:** No cluster-specific validation in deployment testing
8. **Documentation:** Limited operational guidance for cluster management

### Proposed Solution

This proposal addresses these limitations through a phased approach that will:
- Migrate to Kubernetes-native service discovery (K8S resolver)
- Implement proper headless services for cluster formation
- Add cluster health monitoring and alerting
- Configure automated backup strategies
- Implement TLS encryption for cluster communication
- Enable dynamic cluster scaling with automatic member enablement
- Extend validation framework to test cluster-specific functionality
- Provide comprehensive operational documentation

---

## Goals and Objectives

### Primary Goals

1. **Production-Ready Clustering:** Transform the deployment into a production-grade Neo4j cluster that meets enterprise requirements for high availability, disaster recovery, and operational excellence

2. **Cloud-Native Architecture:** Align with Kubernetes best practices by using native service discovery, StatefulSet management, and cloud-native operational patterns

3. **Operational Excellence:** Provide comprehensive monitoring, backup, and operational tooling that enables teams to confidently run Neo4j clusters in production

4. **Developer Experience:** Maintain simplicity for basic deployments while exposing advanced clustering features for production use cases

### Success Criteria

The enhancement will be considered successful when:

1. **Cluster Formation:** Three-node cluster deploys successfully and forms quorum automatically within five minutes
2. **Service Discovery:** Cluster members discover each other using Kubernetes-native mechanisms without manual DNS configuration
3. **High Availability:** Cluster survives single-node failures without data loss and automatically recovers
4. **Data Durability:** All cluster members maintain synchronized data across persistent storage
5. **Monitoring:** Cluster health metrics are visible in Azure Monitor and Neo4j-specific dashboards
6. **Backup and Recovery:** Automated backups execute successfully and restore procedures are documented and tested
7. **Validation:** Deployment validation framework confirms cluster functionality, replication, and failover capabilities
8. **Documentation:** Operations teams can deploy, monitor, and maintain clusters using provided documentation
9. **Performance:** Cluster read performance scales with additional secondary servers
10. **Security:** All cluster communication uses TLS encryption and follows Azure security best practices

---

## Requirements Analysis

### Functional Requirements

#### FR1: Cluster Discovery and Formation

**Requirement:** Neo4j cluster members must discover each other automatically using Kubernetes-native service discovery mechanisms without manual DNS configuration.

**Rationale:** Neo4j clusters require service discovery to form quorum and maintain cluster membership. Kubernetes provides native service discovery through headless services and the Kubernetes API. Using cloud-native discovery eliminates manual DNS management and enables dynamic cluster topology changes.

**Acceptance Criteria:**
- Cluster members discover each other within two minutes of pod startup
- Discovery works consistently across AKS cluster versions and network configurations
- New cluster members automatically join the cluster without manual intervention
- Discovery mechanism does not require external DNS infrastructure
- Cluster formation succeeds even if pods restart in different order

#### FR2: Headless Service Configuration

**Requirement:** Deployment must create a Kubernetes headless service that enables direct pod-to-pod communication and DNS-based service discovery for cluster members.

**Rationale:** Headless services in Kubernetes provide DNS records for each pod, enabling Neo4j cluster members to address each other individually. This is essential for cluster communication protocols that require direct peer-to-peer connections.

**Acceptance Criteria:**
- Headless service is created with clusterIP set to None
- DNS records are created for each StatefulSet pod in the format: podname.servicename.namespace.svc.cluster.local
- Service includes all required Neo4j ports (discovery, bolt, http, backup)
- Service selector correctly identifies Neo4j cluster pods
- DNS resolution works from within Neo4j pods to resolve peer addresses

#### FR3: StatefulSet Configuration

**Requirement:** Neo4j cluster members must be deployed as a StatefulSet with stable network identities, persistent storage, and ordered deployment/scaling.

**Rationale:** StatefulSets provide stable pod identities essential for database clusters. Each pod maintains a consistent hostname and persistent volume binding across restarts, which Neo4j clusters require for stable cluster membership.

**Acceptance Criteria:**
- StatefulSet is configured with appropriate replica count matching nodeCount parameter
- Each pod receives a stable ordinal identifier (neo4j-0, neo4j-1, neo4j-2, etc.)
- Persistent volume claims are created per pod and survive pod restarts
- Pod deployment follows ordered startup sequence (0, 1, 2, ...) to ensure predictable cluster formation
- Scaling operations maintain data integrity and cluster consistency

#### FR4: Persistent Storage Configuration

**Requirement:** Each cluster member must have dedicated persistent storage using Azure Premium SSD with appropriate sizing, performance characteristics, and reclaim policies.

**Rationale:** Neo4j requires persistent storage for database files, transaction logs, and cluster state. Each cluster member needs independent storage to prevent data loss during pod failures.

**Acceptance Criteria:**
- Each cluster member has a dedicated PersistentVolumeClaim
- Storage class uses Azure Premium SSD with appropriate IOPS and throughput
- Volume size is configurable via diskSize parameter
- Reclaim policy is set to Retain to prevent accidental data deletion
- Volumes support dynamic expansion for capacity growth
- Storage performance meets Neo4j minimum requirements for production workloads

#### FR5: Service Discovery Migration

**Requirement:** Deployment must support migration from LIST resolver to Kubernetes-native discovery mechanisms (SRV or K8S resolver types).

**Rationale:** The current LIST resolver requires manual configuration and does not support dynamic cluster topology changes. Migrating to cloud-native discovery enables automatic member discovery and supports elastic scaling.

**Acceptance Criteria:**
- Support for K8S resolver using Kubernetes List Service API
- Support for SRV resolver using Kubernetes headless service SRV records
- Migration path documented for existing deployments using LIST resolver
- Configuration parameter allows selection of resolver type
- Default configuration uses K8S resolver for new deployments
- Backward compatibility maintained for existing deployments during migration period

#### FR6: Cluster Member Initialization

**Requirement:** Cluster members must initialize with correct cluster configuration including minimum cluster size, server roles, and discovery endpoints.

**Rationale:** Neo4j clusters require specific configuration for quorum, roles, and discovery. Incorrect initialization can prevent cluster formation or cause split-brain scenarios.

**Acceptance Criteria:**
- Initial cluster size parameter correctly configures minimum cluster quorum
- Primary and secondary server roles are appropriately assigned
- Discovery endpoints are correctly configured based on resolver type
- Cluster name is consistently configured across all members
- Initial seed list includes all cluster members for reliable bootstrap

#### FR7: Cluster Health Monitoring

**Requirement:** Deployment must expose cluster health metrics including member status, replication lag, quorum health, and cluster topology through monitoring endpoints accessible to Azure Monitor and Prometheus.

**Rationale:** Production clusters require continuous health monitoring to detect failures, performance degradation, and replication issues before they impact applications.

**Acceptance Criteria:**
- Neo4j metrics endpoint is exposed on each pod
- Cluster member status is queryable via Cypher (SHOW SERVERS)
- Replication lag metrics are collected and exposed
- Quorum health status is monitored
- Metrics are accessible to Azure Monitor Container Insights
- Prometheus ServiceMonitor is created for metric scraping
- Alerting rules are defined for critical cluster health issues

#### FR8: Backup and Recovery Strategy

**Requirement:** Deployment must support automated backup configuration with scheduled backups to Azure Blob Storage and documented restore procedures for cluster recovery scenarios.

**Rationale:** Enterprise deployments require reliable backup and disaster recovery capabilities. Clusters need consistent backup strategies that capture cluster state and enable point-in-time recovery.

**Acceptance Criteria:**
- Backup configuration supports online backups without cluster downtime
- Backups are stored in Azure Blob Storage with appropriate retention policies
- Backup schedule is configurable via deployment parameters
- Backup verification procedures are documented
- Restore procedures are documented for single-member and full-cluster recovery scenarios
- Backup encryption is supported using Azure storage encryption
- Backup monitoring alerts on failures

#### FR9: TLS Encryption for Cluster Communication

**Requirement:** All inter-cluster communication must support TLS encryption including discovery, replication, and Raft protocol traffic.

**Rationale:** Production security standards require encryption of data in transit. Cluster communication includes sensitive data and credentials that must be protected.

**Acceptance Criteria:**
- TLS certificates are generated or provided for cluster communication
- Cluster communication uses port 6000 with TLS enabled
- Certificate management procedures are documented
- Certificate rotation is supported without cluster downtime
- Self-signed certificates are supported for development environments
- Integration with Azure Key Vault is supported for certificate storage in production

#### FR10: Dynamic Cluster Scaling

**Requirement:** Deployment must support adding and removing cluster members dynamically through Kubernetes scaling operations with automatic member enablement.

**Rationale:** Production workloads require the ability to scale clusters based on demand. Dynamic scaling enables cost optimization and performance tuning without manual intervention.

**Acceptance Criteria:**
- Cluster can be scaled up by increasing StatefulSet replica count
- New members automatically join the cluster and enable themselves
- Scaling down gracefully removes members with proper cluster transition
- Minimum cluster size is enforced to maintain quorum
- Scaling operations do not cause cluster downtime
- Read replicas can be added independently of core cluster members

### Non-Functional Requirements

#### NFR1: Performance

**Requirement:** Cluster read operations must scale linearly with additional secondary servers, achieving at least eighty percent read throughput improvement when scaling from three to five cluster members under identical workload conditions.

**Rationale:** Horizontal scaling value depends on proportional performance improvements. Poor scaling efficiency indicates architectural issues.

**Acceptance Criteria:**
- Read query throughput measured under consistent workload
- Performance metrics collected before and after scaling operations
- Replication lag remains below one second under normal load
- Write performance meets Neo4j baseline for cluster configurations

#### NFR2: Availability

**Requirement:** Cluster must maintain availability during single-node failures with automatic failover completing within thirty seconds and no data loss.

**Rationale:** High availability clusters must tolerate individual node failures without service interruption.

**Acceptance Criteria:**
- Read and write operations continue during single-node failure
- Leader election completes within thirty seconds
- Client connections automatically redirect to available members
- No committed transactions are lost during failover
- Failed node can rejoin cluster after recovery without manual intervention

#### NFR3: Reliability

**Requirement:** Cluster deployment must achieve ninety-nine point nine percent success rate across diverse AKS configurations including multiple Kubernetes versions, regions, and node pool configurations.

**Rationale:** Enterprise customers require predictable deployments across varied Azure environments.

**Acceptance Criteria:**
- Deployment tested across supported AKS Kubernetes versions (1.28+)
- Deployment validated in multiple Azure regions
- Deployment succeeds with various node pool VM sizes
- Network policies and security configurations do not prevent cluster formation
- Deployment automation includes retry logic for transient failures

#### NFR4: Maintainability

**Requirement:** Operational procedures for cluster maintenance including upgrades, configuration changes, and troubleshooting must be documented with runbooks that enable operations teams to resolve common issues without Neo4j expert assistance.

**Rationale:** Production systems require maintainable architectures that operations teams can support.

**Acceptance Criteria:**
- Operations documentation covers all day-two operational tasks
- Troubleshooting runbooks address common failure scenarios
- Upgrade procedures are documented and tested
- Configuration change procedures minimize risk of cluster disruption
- Monitoring dashboards enable rapid issue diagnosis

#### NFR5: Security

**Requirement:** Cluster deployment must follow Azure and Neo4j security best practices including network isolation, encryption in transit and at rest, secrets management, and audit logging.

**Rationale:** Enterprise security policies require comprehensive security controls for production database deployments.

**Acceptance Criteria:**
- Network policies restrict cluster communication to necessary ports
- Secrets are stored in Azure Key Vault, not in clear text
- Audit logging captures cluster administrative actions
- Role-based access control integrates with Azure Active Directory
- Security configuration meets common compliance frameworks (SOC2, ISO27001)

#### NFR6: Observability

**Requirement:** All cluster operations, state changes, and performance metrics must be visible through Azure Monitor with integration to existing monitoring infrastructure including log aggregation, metric collection, and alerting.

**Rationale:** Production operations depend on comprehensive observability to maintain service levels.

**Acceptance Criteria:**
- All cluster events are logged to Azure Monitor
- Metrics are collected at one-minute intervals
- Dashboards visualize cluster health and performance
- Alerts notify operators of critical issues
- Logs include sufficient context for troubleshooting
- Integration with existing Azure monitoring infrastructure

---

## Architecture Design

### High-Level Architecture

The enhanced clustering architecture builds upon the current Bicep and Helm deployment model, extending it with cloud-native clustering capabilities.

#### Component Overview

**Infrastructure Layer (Bicep):**
- AKS cluster with appropriate node pools for system and Neo4j workloads
- Virtual network with subnet isolation for cluster traffic
- Managed identity for Kubernetes workload identity integration
- Storage classes for premium SSD persistent volumes
- Azure Monitor Log Analytics workspace for centralized logging
- Network security groups for traffic control

**Application Layer (Helm Chart):**
- StatefulSet for Neo4j cluster members with stable identities
- Headless service for cluster member discovery
- LoadBalancer service for external client access
- ConfigMaps for Neo4j configuration settings
- Secrets for credentials and certificates
- ServiceAccount with RBAC permissions for K8S service discovery
- PersistentVolumeClaims per cluster member for data storage

**Monitoring Layer:**
- Azure Monitor Container Insights for pod metrics
- Prometheus ServiceMonitor for Neo4j-specific metrics
- Azure Monitor Workbooks for cluster dashboards
- Alert rules for critical cluster health conditions

**Backup Layer:**
- CronJob for scheduled backups
- Azure Blob Storage for backup retention
- Backup verification jobs
- Restore runbooks and procedures

### Service Discovery Architecture

The cluster will migrate from LIST resolver to Kubernetes-native discovery using a phased approach.

#### Phase 1: LIST Resolver (Current State)

**Mechanism:**
Each Neo4j cluster member is configured with a hard-coded list of all cluster member addresses. Pod names follow StatefulSet naming convention (neo4j-0, neo4j-1, neo4j-2).

**Configuration:**
```
dbms.cluster.discovery.resolver_type=LIST
dbms.cluster.endpoints=neo4j-0:6000,neo4j-1:6000,neo4j-2:6000
```

**Advantages:**
- Simple and predictable
- No external dependencies
- Works reliably for fixed cluster sizes

**Limitations:**
- Requires manual configuration updates for cluster size changes
- Not cloud-native
- Difficult to integrate with auto-scaling

#### Phase 2: SRV Resolver (Intermediate Evolution)

**Mechanism:**
Kubernetes headless service automatically creates SRV DNS records for each pod. Neo4j queries SRV records to discover cluster members.

**Configuration:**
```
dbms.cluster.discovery.resolver_type=SRV
server.cluster.advertised_address=neo4j-0.neo4j-headless.neo4j.svc.cluster.local:6000
dbms.cluster.endpoints=_discovery._tcp.neo4j-headless.neo4j.svc.cluster.local:0
```

**Advantages:**
- Leverages Kubernetes-native DNS service discovery
- Automatically reflects cluster topology changes
- More cloud-native than LIST resolver
- No RBAC configuration required

**Limitations:**
- Depends on DNS resolution performance
- DNS caching can delay topology updates

#### Phase 3: K8S Resolver (Production-Ready Target)

**Mechanism:**
Neo4j uses Kubernetes API directly to query service endpoints based on label selectors. Requires ServiceAccount with permissions to list services.

**Configuration:**
```
dbms.cluster.discovery.resolver_type=K8S
dbms.kubernetes.label_selector=app=neo4j,component=cluster
dbms.kubernetes.discovery.service_port_name=discovery
server.cluster.advertised_address=neo4j-0.neo4j-headless.neo4j.svc.cluster.local:6000
```

**Advantages:**
- True Kubernetes-native integration
- No DNS dependencies
- Immediate reflection of topology changes
- Label-based filtering for multi-tenant environments
- Most flexible for dynamic scaling

**Limitations:**
- Requires RBAC configuration
- Additional Kubernetes API calls
- Slightly more complex setup

**Recommended Approach:**
For production deployments, K8S resolver provides the best balance of reliability, cloud-native integration, and operational flexibility.

### Network Architecture

#### Service Types

**Headless Service (cluster-internal):**
- Name: neo4j-headless
- ClusterIP: None
- Purpose: Enables DNS-based discovery of individual pods
- Ports: discovery (6000), bolt (7687), http (7474), https (7473), backup (6362)
- Selectors: app=neo4j, component=cluster

**LoadBalancer Service (external access):**
- Name: neo4j-lb
- Type: LoadBalancer
- Purpose: Provides external client access to Neo4j cluster
- Ports: bolt (7687), http (7474), https (7473)
- Selectors: app=neo4j, component=cluster
- Annotations: Azure LoadBalancer configuration for static IP, SKU, etc.

#### Port Configuration

Following Neo4j 5.x and Neo4j 2025 port standards:

- **6000 (Discovery/Cluster):** Internal cluster communication including Raft consensus and discovery (replaces legacy port 5000)
- **7687 (Bolt):** Client database connections using Bolt protocol
- **7474 (HTTP):** Neo4j Browser and HTTP API
- **7473 (HTTPS):** Encrypted Neo4j Browser and HTTP API (when TLS enabled)
- **6362 (Backup):** Backup protocol port for cluster backups
- **2004 (Metrics):** Prometheus metrics endpoint (optional)

### Storage Architecture

#### Persistent Volume Configuration

Each cluster member requires independent persistent storage with the following characteristics:

**Storage Class Configuration:**
- Name: neo4j-premium
- Provisioner: Azure Disk CSI Driver
- SKU: Premium_LRS (Premium SSD locally-redundant storage)
- Reclaim Policy: Retain (prevents accidental data deletion)
- Volume Binding Mode: WaitForFirstConsumer (optimizes zone placement)
- Allow Volume Expansion: true (enables online volume resizing)

**Volume Characteristics:**
- Size: Configurable via diskSize parameter (default 32 GB, maximum 4096 GB)
- IOPS: Scales with disk size following Azure Premium SSD specifications
- Throughput: Scales with disk size
- Latency: Sub-millisecond for Premium SSD
- Availability: Locally redundant within single availability zone

**Data Layout Per Pod:**
- /data/transactions: Transaction logs for write-ahead logging
- /data/databases: Database files including graph store and indexes
- /logs: Neo4j server logs
- /metrics: Metrics output files
- /import: Data import directory for bulk loading

**Volume Expansion Strategy:**
When diskSize parameter is increased:
- PersistentVolumeClaim is updated with new size
- Azure Disk is expanded online without pod restart
- Filesystem is automatically resized
- No data migration required

### High Availability Architecture

#### Quorum and Consistency

Neo4j clusters use Raft consensus protocol to maintain consistency across cluster members.

**Cluster Roles:**
- **Primary Server:** Handles all write operations and coordinates cluster state
- **Secondary Servers:** Handle read operations and participate in leader election
- **Quorum Requirement:** Majority of servers must be available (e.g., 2 of 3, 3 of 5)

**Recommended Cluster Sizes:**
- **3 Nodes:** Minimum production cluster (tolerates 1 failure)
- **5 Nodes:** High availability cluster (tolerates 2 failures)
- **7+ Nodes:** Large-scale deployments (tolerates 3+ failures)

**Anti-Pattern - Avoid 2-Node Clusters:**
Two-node clusters cannot form quorum if one node fails. Always use odd-numbered cluster sizes (3, 5, 7) to ensure quorum during failures.

#### Failure Scenarios and Recovery

**Single-Node Failure:**
- Cluster continues operating if quorum is maintained
- Leader election occurs if primary fails (completes in 10-30 seconds)
- Read and write operations continue on available members
- Failed node can rejoin cluster after recovery
- No data loss for committed transactions

**Multi-Node Failure (Quorum Lost):**
- Cluster becomes read-only to prevent split-brain
- No new writes accepted until quorum is restored
- Automatic recovery when sufficient members return
- Manual intervention may be required for severe failures

**Network Partition:**
- Partition with quorum continues operating
- Partition without quorum becomes read-only
- Automatic reconciliation when partition heals
- Raft protocol prevents split-brain scenarios

#### Pod Distribution Strategy

To maximize availability, cluster member pods should be distributed across:

**Availability Zones:**
Use pod anti-affinity rules to distribute pods across Azure availability zones within the region. This protects against zone-level failures.

**Kubernetes Nodes:**
Use pod anti-affinity rules to prevent multiple cluster members from running on the same Kubernetes node. This protects against node-level failures.

**Example Anti-Affinity Configuration:**
The Helm chart should configure pod anti-affinity to prefer different nodes and zones while allowing deployment when insufficient nodes are available (soft anti-affinity rather than hard requirements).

### Security Architecture

#### Authentication and Authorization

**Initial Authentication:**
- Default neo4j user with password provided during deployment
- Password stored as Kubernetes Secret
- Secret references Azure Key Vault for production deployments

**Production Authentication:**
- Integration with Azure Active Directory for enterprise authentication
- Role-based access control (RBAC) for database permissions
- Service principal support for application authentication

#### Encryption

**Encryption in Transit:**
- TLS encryption for client connections (Bolt and HTTPS)
- TLS encryption for inter-cluster communication (discovery and replication)
- Certificate management via Azure Key Vault or Kubernetes cert-manager
- Support for both self-signed and CA-signed certificates

**Encryption at Rest:**
- Azure Disk encryption for persistent volumes
- Transparent encryption using Azure Storage Service Encryption
- No application-level changes required

#### Network Security

**Network Policies:**
- Restrict ingress to Neo4j pods to only required ports
- Limit egress to necessary services (Azure API, Azure Monitor)
- Prevent unauthorized inter-pod communication
- Default deny posture with explicit allow rules

**Service Account Permissions:**
For K8S resolver, ServiceAccount requires minimal permissions:
- Resource: services
- Verbs: get, list, watch
- Namespace: neo4j namespace only
- No cluster-wide permissions required

### Monitoring Architecture

#### Metrics Collection

**Neo4j Metrics:**
- Exposed via Prometheus endpoint on port 2004
- Includes database, cluster, JVM, and transaction metrics
- Metrics are scraped every 60 seconds
- Retention period follows Azure Monitor configuration

**Cluster-Specific Metrics:**
- Cluster member status (online, offline)
- Leader election events
- Replication lag per secondary server
- Quorum health status
- Catchup status for recovering members

**Azure Monitor Integration:**
- Container Insights collects pod and node metrics
- Log Analytics workspace aggregates all logs
- Custom metrics pushed to Azure Monitor Metrics
- Workbooks visualize cluster health and performance

#### Alerting Strategy

**Critical Alerts (Immediate Response Required):**
- Cluster quorum lost
- All cluster members offline
- Persistent volume approaching capacity (90% full)
- Backup failures
- TLS certificate expiration within 7 days

**Warning Alerts (Investigation Required):**
- Single cluster member offline
- Replication lag exceeds 10 seconds
- High memory utilization (above 85%)
- Slow query detected
- Backup duration increasing

**Informational Alerts (Awareness Only):**
- Cluster scaling events
- Leader election completed
- Configuration changes applied
- Successful backup completed

### Backup Architecture

#### Backup Strategy

**Online Backups:**
- Scheduled backups execute while cluster remains online
- Backups captured from secondary servers to minimize primary load
- Consistency guaranteed via Neo4j backup protocol
- Incremental backups supported for large databases

**Backup Schedule:**
- Full backup: Daily during off-peak hours (configurable)
- Incremental backup: Every 6 hours (configurable)
- Retention: 7 daily, 4 weekly, 12 monthly (configurable)

**Backup Storage:**
- Azure Blob Storage for durability and cost-effectiveness
- Geo-redundant storage (GRS) for disaster recovery scenarios
- Lifecycle policies for automatic retention management
- Backup encryption using Azure Storage Service Encryption

**Backup Verification:**
- Weekly verification job validates backup integrity
- Verification restores backup to temporary instance
- Automated tests confirm database accessibility
- Alerts on verification failures

#### Restore Procedures

**Single-Member Restore:**
Used when one cluster member has corrupted data but cluster remains operational.

Steps:
1. Remove failed member from cluster
2. Delete corrupted PersistentVolumeClaim
3. Create new PVC and pod
4. Restore from backup to new pod
5. Rejoin cluster and synchronize

**Full-Cluster Restore:**
Used for disaster recovery when entire cluster is lost.

Steps:
1. Deploy new cluster infrastructure
2. Restore backup to first cluster member
3. Start first member in standalone mode
4. Verify data integrity
5. Add additional cluster members
6. Members synchronize from first member
7. Validate cluster formation and data consistency

---

## Implementation Plan

### Overview

The implementation is organized into five distinct phases, each building upon the previous phase. This phased approach minimizes risk, enables incremental validation, and allows for learning and adjustment between phases.

**Timeline:** Each phase includes buffer time for testing, validation, and documentation. Total estimated timeline is 8-10 weeks for complete implementation.

**Validation Strategy:** Each phase concludes with comprehensive testing using the deployments/ validation framework, extended with cluster-specific test scenarios.

---

### Phase 1: Foundation - Headless Services and StatefulSet Configuration

**Duration:** 2 weeks

**Objective:** Establish the foundational Kubernetes architecture for clustering by implementing headless services, configuring StatefulSets with proper pod anti-affinity, and ensuring persistent storage is correctly configured per cluster member.

**Prerequisites:**
- Current standalone deployment working and validated
- Access to AKS test environment
- Deployments validation framework operational

#### Requirements

##### R1.1: Headless Service Implementation

Create a Kubernetes headless service that enables DNS-based discovery of individual Neo4j cluster member pods. The headless service must provide stable DNS names for each pod in the StatefulSet, following the pattern podname.servicename.namespace.svc.cluster.local.

**DNS Record Pattern:**
- neo4j-0.neo4j-headless.neo4j.svc.cluster.local
- neo4j-1.neo4j-headless.neo4j.svc.cluster.local
- neo4j-2.neo4j-headless.neo4j.svc.cluster.local

**Service Configuration Requirements:**
- Service must set clusterIP to None to enable headless behavior
- Service must include all Neo4j ports required for cluster communication
- Port naming must follow Kubernetes conventions for SRV record generation
- Service selector must correctly identify Neo4j cluster pods
- Service must be created before StatefulSet to ensure DNS availability

**Port Requirements:**
- discovery: 6000 (cluster communication and Raft protocol)
- bolt: 7687 (client connections)
- http: 7474 (Neo4j Browser and HTTP API)
- https: 7473 (encrypted connections when TLS enabled)
- backup: 6362 (backup protocol)
- metrics: 2004 (Prometheus metrics, optional)

##### R1.2: StatefulSet Pod Anti-Affinity Configuration

Configure StatefulSet pod anti-affinity rules to distribute cluster member pods across different Kubernetes nodes and, where possible, across different Azure availability zones.

**Anti-Affinity Strategy:**
Use preferredDuringSchedulingIgnoredDuringExecution (soft anti-affinity) rather than required anti-affinity. This ensures deployments succeed even when insufficient nodes are available for hard anti-affinity, while still achieving distribution when possible.

**Node Distribution:**
Prefer scheduling pods on different Kubernetes nodes to protect against node failures. Weight this preference highly (e.g., weight 100).

**Zone Distribution:**
Prefer scheduling pods in different availability zones to protect against zone failures. Weight this preference moderately (e.g., weight 50) as zone distribution is valuable but not always achievable depending on cluster configuration.

**Rationale:**
Soft anti-affinity enables successful deployments in development environments with limited node counts while achieving optimal distribution in production multi-zone AKS clusters.

##### R1.3: Persistent Storage Per Cluster Member

Ensure each cluster member receives a dedicated PersistentVolumeClaim that persists across pod restarts and maintains data locality.

**Storage Requirements:**
- Each StatefulSet pod must have a volumeClaimTemplate that creates a dedicated PVC
- PVC naming must follow StatefulSet conventions: data-neo4j-0, data-neo4j-1, data-neo4j-2
- Storage class must use Azure Premium SSD (neo4j-premium storage class)
- Reclaim policy must be Retain to prevent accidental data deletion
- Volume binding mode must be WaitForFirstConsumer for optimal zone placement
- PVC size must be configurable via diskSize parameter

**Volume Mount Configuration:**
- Primary data mount point: /data
- Logs mount point: /logs (may use same PVC or separate)
- Ensure correct ownership and permissions for Neo4j process

##### R1.4: Helm Chart Parameter Structure

Define clear Helm chart parameters that control cluster configuration while maintaining backward compatibility with standalone deployments.

**Key Parameters:**
- nodeCount: number of cluster members (1 for standalone, 3-10 for cluster)
- deploymentMode: automatically determined as "standalone" (nodeCount=1) or "cluster" (nodeCount>=3)
- enablePodAntiAffinity: boolean to control anti-affinity rules (default true for clusters)
- storageClassName: name of storage class to use (default neo4j-premium)
- diskSize: size of persistent volume per pod in GB

**Backward Compatibility:**
Existing standalone deployments (nodeCount=1) must continue to work without requiring configuration changes. The headless service and anti-affinity rules should not negatively impact standalone deployments.

##### R1.5: Bicep Template Integration

Update Bicep templates to pass appropriate parameters to Helm chart for cluster configuration while maintaining clean separation between infrastructure (Bicep) and application (Helm) layers.

**Bicep Responsibilities:**
- Determine cluster vs standalone mode based on nodeCount parameter
- Pass cluster configuration to neo4j-app.bicep module
- Ensure AKS node pool has sufficient capacity for cluster deployments
- Configure appropriate VM sizes for cluster workloads

**Helm Integration Points:**
- neo4j-app.bicep module invokes helm-deployment.bicep with cluster parameters
- helm-deployment.bicep generates Helm values for headless service and StatefulSet
- Deployment script creates headless service as part of Helm chart deployment

#### Phase 1 Todo List

1. **Create headless service specification** - Define Kubernetes headless service YAML structure with all required ports (discovery, bolt, http, https, backup, metrics) and correct selector labels for Neo4j cluster pods

2. **Configure StatefulSet pod anti-affinity rules** - Implement soft anti-affinity rules preferring different nodes (weight 100) and different zones (weight 50) using preferredDuringSchedulingIgnoredDuringExecution

3. **Update StatefulSet volumeClaimTemplate** - Configure persistent storage template to create dedicated PVC per pod with correct storage class, size, and reclaim policy

4. **Modify helm-deployment.bicep script** - Update deployment script to create headless service before StatefulSet, ensuring DNS records are available when pods start

5. **Add cluster mode detection logic** - Implement logic in Bicep and Helm to automatically determine standalone vs cluster mode based on nodeCount parameter and set appropriate configuration

6. **Update Helm chart parameters** - Add new parameters for headless service configuration, anti-affinity rules, and cluster-specific settings while maintaining backward compatibility

7. **Integrate with neo4j-app.bicep** - Update neo4j-app.bicep module to pass cluster configuration parameters to helm-deployment.bicep

8. **Create validation test for headless service** - Add test cases to deployments/ framework that verify headless service is created with correct configuration

9. **Create validation test for StatefulSet** - Add test cases that verify StatefulSet creates correct number of pods with stable identities and persistent storage

10. **Create validation test for DNS resolution** - Add test cases that verify DNS records are created for each pod and are resolvable from within cluster

11. **Create validation test for pod distribution** - Add test cases that verify pods are distributed across nodes and zones according to anti-affinity rules when infrastructure supports it

12. **Update documentation** - Document headless service architecture, StatefulSet configuration, and storage persistence model in architecture documentation

13. **Perform code review and testing** - Conduct comprehensive code review of all Bicep and Helm changes, execute validation tests across multiple AKS environments (single-zone, multi-zone, different VM sizes), verify backward compatibility with standalone deployments, and validate pod distribution across nodes

---

### Phase 2: Service Discovery - SRV Resolver Migration

**Duration:** 2 weeks

**Objective:** Migrate from LIST resolver to SRV resolver, leveraging Kubernetes-native DNS service discovery through headless service SRV records. This provides cloud-native discovery without requiring Kubernetes RBAC configuration.

**Prerequisites:**
- Phase 1 completed and validated
- Headless service operational with correct SRV records
- DNS resolution tested from pods

#### Requirements

##### R2.1: SRV Resolver Configuration

Configure Neo4j to use SRV resolver for cluster member discovery, utilizing SRV DNS records automatically created by Kubernetes headless service.

**Configuration Requirements:**
- Set dbms.cluster.discovery.resolver_type to SRV
- Configure dbms.cluster.endpoints with headless service DNS name and port 0
- Configure server.cluster.advertised_address for each pod using pod-specific DNS name
- Ensure discovery port is correctly named in headless service definition

**SRV Record Pattern:**
Kubernetes creates SRV records following this pattern:
_portname._protocol.servicename.namespace.svc.cluster.local

For Neo4j discovery port:
_discovery._tcp.neo4j-headless.neo4j.svc.cluster.local

**Pod-Specific Configuration:**
Each pod must advertise its own unique DNS name:
- Pod 0: neo4j-0.neo4j-headless.neo4j.svc.cluster.local:6000
- Pod 1: neo4j-1.neo4j-headless.neo4j.svc.cluster.local:6000
- Pod 2: neo4j-2.neo4j-headless.neo4j.svc.cluster.local:6000

##### R2.2: Headless Service Port Naming

Ensure headless service ports are correctly named to generate proper SRV records.

**Port Naming Requirements:**
- Discovery port must be named "discovery" (not "cluster" or other names)
- Port names must be lowercase and alphanumeric
- Port names must match Neo4j configuration expectations
- All ports should follow consistent naming convention

**SRV Record Validation:**
Verify that Kubernetes generates correct SRV records after service creation. Records should include priority, weight, port, and target for each pod.

##### R2.3: Dynamic Configuration with Pod Identity

Implement mechanism to dynamically configure each pod's advertised address based on its StatefulSet ordinal and namespace.

**Implementation Approach:**
Use Kubernetes downward API or init containers to inject pod-specific configuration:
- Pod name from metadata.name
- Namespace from metadata.namespace
- Service name from configuration
- Construct full DNS name: $(POD_NAME).$(SERVICE_NAME).$(NAMESPACE).svc.cluster.local

**Configuration Injection:**
Neo4j configuration supports environment variable substitution. Use environment variables to inject pod-specific values:
- NEO4J_server_cluster_advertised__address=$(POD_DNS_NAME):6000

##### R2.4: Cluster Endpoint Configuration

Configure cluster endpoints to point to SRV DNS record with port set to zero, as required by SRV resolver specification.

**Critical Requirement:**
When using SRV resolver, the port in dbms.cluster.endpoints must be 0. The actual port is retrieved from the SRV record. Using a non-zero port will cause discovery to fail.

Correct configuration:
```
dbms.cluster.endpoints=_discovery._tcp.neo4j-headless.neo4j.svc.cluster.local:0
```

Incorrect configuration (will fail):
```
dbms.cluster.endpoints=_discovery._tcp.neo4j-headless.neo4j.svc.cluster.local:6000
```

##### R2.5: Minimum Cluster Size Configuration

Configure minimum cluster size parameter to establish quorum requirements for cluster formation.

**Configuration Requirement:**
- Set neo4j.minimumClusterSize to match nodeCount for initial cluster formation
- For 3-node cluster: minimumClusterSize=3
- For 5-node cluster: minimumClusterSize=5
- Minimum cluster size should be majority of total cluster size for production

**Rationale:**
Minimum cluster size ensures cluster does not prematurely form with insufficient members. For a 3-node cluster, all 3 members should be available before cluster formation begins.

##### R2.6: Migration Path from LIST to SRV

Provide clear migration path for deployments currently using LIST resolver to migrate to SRV resolver without data loss.

**Migration Steps:**
1. Verify headless service is deployed and SRV records are created
2. Perform rolling update of StatefulSet pods with new SRV configuration
3. Monitor cluster health during migration
4. Verify all pods rejoin cluster successfully
5. Validate cluster functionality after migration

**Rollback Plan:**
If migration encounters issues:
1. Revert to LIST resolver configuration
2. Perform rolling restart with LIST configuration
3. Verify cluster reforms with LIST resolver
4. Investigate SRV configuration issues before retry

##### R2.7: DNS Resolution Validation

Implement validation that confirms SRV records are correctly created and resolvable before attempting cluster formation.

**Validation Requirements:**
- Init container verifies SRV records exist before starting Neo4j
- DNS resolution is tested from within pod network
- Minimum number of SRV records matches expected cluster size
- Validation failure delays pod startup with clear error message

**Validation Tools:**
Use dig or nslookup to query SRV records:
```
dig _discovery._tcp.neo4j-headless.neo4j.svc.cluster.local SRV
```

Expected output shows SRV records for each pod with correct port and target.

#### Phase 2 Todo List

1. **Update Neo4j configuration for SRV resolver** - Change resolver type from LIST to SRV in Helm chart Neo4j configuration template

2. **Configure cluster endpoints with SRV DNS name** - Set dbms.cluster.endpoints to SRV record pattern with port 0 as required by SRV specification

3. **Implement pod identity injection** - Use Kubernetes downward API to inject pod name, namespace, and service name as environment variables accessible to Neo4j configuration

4. **Configure advertised address with pod DNS** - Set server.cluster.advertised_address to pod-specific DNS name using injected environment variables

5. **Verify headless service port naming** - Ensure discovery port is named "discovery" in headless service definition to generate correct SRV records

6. **Configure minimum cluster size parameter** - Set neo4j.minimumClusterSize Helm parameter to match nodeCount for proper quorum configuration

7. **Create SRV record validation init container** - Implement init container that verifies SRV records exist and are resolvable before starting Neo4j

8. **Update Helm chart with SRV configuration** - Modify Helm chart to conditionally use SRV resolver for cluster mode (nodeCount >= 3)

9. **Document migration procedure from LIST to SRV** - Create runbook documenting step-by-step migration for existing deployments

10. **Create validation test for SRV records** - Add test cases to deployments/ framework that verify SRV records are created with correct format and content

11. **Create validation test for cluster formation with SRV** - Add test cases that deploy 3-node cluster with SRV resolver and verify successful cluster formation

12. **Create validation test for DNS resolution** - Add test cases that verify each pod can resolve SRV records and discover other cluster members

13. **Update architecture documentation** - Document SRV resolver architecture, DNS record patterns, and cluster discovery mechanism

14. **Perform code review and testing** - Conduct comprehensive code review of SRV resolver implementation, execute validation tests with 3-node and 5-node clusters, verify cluster forms successfully, test rolling restart scenarios, validate migration from LIST to SRV, and confirm cluster remains stable during DNS updates

---

### Phase 3: Production-Ready Discovery - K8S Resolver and RBAC

**Duration:** 2 weeks

**Objective:** Implement Kubernetes-native service discovery using K8S resolver with appropriate RBAC permissions. This provides the most cloud-native discovery mechanism with immediate topology updates and no DNS dependencies.

**Prerequisites:**
- Phase 2 completed and validated
- SRV resolver operational and tested
- Understanding of Kubernetes RBAC model

#### Requirements

##### R3.1: ServiceAccount Creation

Create dedicated Kubernetes ServiceAccount for Neo4j pods with minimal permissions required for service discovery.

**ServiceAccount Requirements:**
- Name: neo4j-sa
- Namespace: neo4j (or deployment-specific namespace)
- No cluster-wide permissions
- Used by all Neo4j cluster member pods

**Pod Association:**
StatefulSet must specify serviceAccountName: neo4j-sa to bind pods to the ServiceAccount.

##### R3.2: RBAC Role Definition

Create Kubernetes Role with minimal permissions required for K8S resolver to query service endpoints.

**Role Requirements:**
- Name: neo4j-service-reader
- Namespace: neo4j (same as Neo4j deployment)
- API Groups: [""] (core API group)
- Resources: ["services"]
- Verbs: ["get", "list", "watch"]

**Permission Scope:**
Role must be namespace-scoped, not cluster-scoped. Neo4j pods only need to discover services within their own namespace, not across the entire cluster.

**Rationale:**
Minimal permissions follow principle of least privilege. Neo4j does not need permissions to modify services, only read access for discovery.

##### R3.3: RoleBinding Configuration

Create RoleBinding that grants the neo4j-service-reader Role to the neo4j-sa ServiceAccount.

**RoleBinding Requirements:**
- Name: neo4j-service-reader-binding
- Namespace: neo4j
- Subjects: ServiceAccount neo4j-sa in neo4j namespace
- RoleRef: Role neo4j-service-reader

**Verification:**
After creating RoleBinding, verify permissions using kubectl auth can-i:
```
kubectl auth can-i list services --as=system:serviceaccount:neo4j:neo4j-sa -n neo4j
```
Expected output: yes

##### R3.4: K8S Resolver Configuration

Configure Neo4j to use K8S resolver with appropriate label selector and service port name.

**Configuration Requirements:**
- Set dbms.cluster.discovery.resolver_type to K8S
- Set dbms.kubernetes.label_selector to identify Neo4j cluster services
- Set dbms.kubernetes.discovery.service_port_name to "discovery"
- Configure server.cluster.advertised_address for each pod

**Label Selector:**
Use label selector to identify services belonging to this specific Neo4j cluster:
```
app=neo4j,component=cluster,release=neo4j
```

This allows multiple Neo4j clusters to coexist in the same namespace without interfering with each other's discovery.

**Service Port Name:**
The discovery port on the headless service must be named "discovery" to match the service_port_name configuration.

##### R3.5: Service Labeling Strategy

Ensure headless service and LoadBalancer service are labeled correctly for discovery by K8S resolver.

**Required Labels:**
- app: neo4j (identifies Neo4j application)
- component: cluster (distinguishes cluster services from other Neo4j services)
- release: {release-name} (identifies specific deployment instance)
- version: {neo4j-version} (documents Neo4j version for troubleshooting)

**Label Consistency:**
Service labels must match the label selector configured in Neo4j K8S resolver settings. Mismatched labels will prevent service discovery.

##### R3.6: Helm Chart RBAC Integration

Update Helm chart to create ServiceAccount, Role, and RoleBinding as part of deployment.

**Implementation Requirements:**
- RBAC resources created before StatefulSet
- RBAC resources scoped to deployment namespace
- RBAC resources labeled for ownership tracking
- RBAC resources documented in Helm chart README

**Conditional Creation:**
RBAC resources should only be created when K8S resolver is enabled. For backward compatibility with SRV resolver, make RBAC creation conditional on resolver type.

##### R3.7: Migration Path from SRV to K8S

Provide migration path from SRV resolver to K8S resolver with minimal cluster disruption.

**Migration Steps:**
1. Deploy RBAC resources (ServiceAccount, Role, RoleBinding) to cluster
2. Verify RBAC permissions using kubectl auth can-i
3. Update StatefulSet to use neo4j-sa ServiceAccount
4. Perform rolling update of pods with K8S resolver configuration
5. Monitor cluster health during migration
6. Verify pods discover each other using K8S API
7. Validate cluster functionality after migration

**Validation:**
Check pod logs for K8S resolver activity:
```
kubectl logs neo4j-0 -n neo4j | grep -i "k8s.*discovery"
```

Successful K8S discovery logs show successful Kubernetes API queries and discovered service endpoints.

##### R3.8: Resolver Type Parameter

Add Helm parameter to select resolver type (LIST, SRV, K8S) with sensible defaults.

**Parameter Design:**
- Name: discoveryResolverType
- Allowed Values: LIST, SRV, K8S
- Default for Standalone (nodeCount=1): LIST
- Default for Cluster (nodeCount>=3): K8S
- User can override default via parameter

**Backward Compatibility:**
Existing deployments continue using LIST resolver unless explicitly changed. Migration to SRV or K8S requires explicit parameter update.

#### Phase 3 Todo List

1. **Create ServiceAccount specification** - Define ServiceAccount YAML for Neo4j pods with appropriate metadata and labels

2. **Create Role specification** - Define Role YAML with minimal permissions (get, list, watch services) scoped to namespace

3. **Create RoleBinding specification** - Define RoleBinding YAML connecting ServiceAccount to Role

4. **Update Helm chart to create RBAC resources** - Add ServiceAccount, Role, and RoleBinding to Helm chart templates with appropriate conditionals

5. **Configure StatefulSet to use ServiceAccount** - Set serviceAccountName in StatefulSet pod spec to reference neo4j-sa

6. **Update Neo4j configuration for K8S resolver** - Change resolver type to K8S and configure label selector and service port name

7. **Configure label selector for service discovery** - Set dbms.kubernetes.label_selector to match headless service labels

8. **Update headless service labels** - Add required labels (app, component, release, version) to headless service definition

9. **Add resolver type parameter to Helm chart** - Create discoveryResolverType parameter with validation and defaults based on cluster mode

10. **Implement conditional RBAC creation** - Create RBAC resources only when K8S resolver is selected

11. **Create RBAC validation test** - Add test cases to deployments/ framework that verify ServiceAccount, Role, and RoleBinding are created correctly

12. **Create K8S resolver validation test** - Add test cases that verify pods can list services using ServiceAccount permissions

13. **Create cluster formation test with K8S resolver** - Add test cases that deploy cluster with K8S resolver and verify successful discovery and formation

14. **Document RBAC configuration and permissions** - Create documentation explaining RBAC setup, minimal permissions, and security implications

15. **Document migration path from SRV to K8S** - Create runbook for migrating existing clusters from SRV to K8S resolver

16. **Perform code review and testing** - Conduct comprehensive code review of RBAC implementation, execute validation tests with all resolver types (LIST, SRV, K8S), verify cluster formation with K8S resolver, test RBAC permission validation, validate migration scenarios, and confirm pods can discover services via Kubernetes API

---

### Phase 4: Operational Excellence - Monitoring, Backup, and Security

**Duration:** 3 weeks

**Objective:** Implement production-grade operational capabilities including cluster health monitoring, automated backup strategies, and security hardening with TLS encryption.

**Prerequisites:**
- Phase 3 completed and validated
- Cluster discovery operational with K8S resolver
- Azure Monitor workspace configured

#### Requirements

##### R4.1: Cluster Health Monitoring

Implement comprehensive monitoring of cluster-specific health metrics beyond standard pod and container metrics.

**Metrics Requirements:**

**Cluster Membership Metrics:**
- Number of cluster members (expected vs actual)
- Cluster member status per node (online, offline, unknown)
- Leader election events and current leader identity
- Quorum health status (quorum available vs lost)

**Replication Metrics:**
- Replication lag per secondary server (milliseconds)
- Catchup status for recovering members
- Transaction log position per member
- Sync status across cluster members

**Performance Metrics:**
- Write throughput on primary server (transactions per second)
- Read throughput on secondary servers
- Query execution time distribution
- Connection count per member

**Resource Metrics:**
- Memory utilization per pod (heap, pagecache, total)
- CPU utilization per pod
- Disk I/O operations per second
- Network throughput for cluster communication

##### R4.2: Prometheus Integration

Configure Neo4j metrics endpoint and Prometheus ServiceMonitor for automated metric scraping.

**Metrics Endpoint Configuration:**
- Enable Neo4j Prometheus metrics on port 2004
- Configure metrics exposure in Neo4j configuration
- Expose metrics port in pod and service definitions
- Ensure metrics endpoint is accessible to Prometheus

**ServiceMonitor Configuration:**
- Create Prometheus ServiceMonitor for Neo4j cluster
- Configure scrape interval (60 seconds recommended)
- Set appropriate timeout and evaluation interval
- Add metric relabeling for cluster identification

**Prometheus Deployment:**
If Prometheus is not already deployed in AKS cluster, provide guidance for deploying Prometheus Operator using Helm chart or Azure Monitor managed Prometheus.

##### R4.3: Azure Monitor Integration

Integrate Neo4j cluster metrics with Azure Monitor for centralized monitoring and alerting.

**Log Analytics Integration:**
- Configure Container Insights for Neo4j namespace
- Stream Neo4j logs to Log Analytics workspace
- Create custom log queries for cluster events
- Set up log-based alerts for critical events

**Metrics Integration:**
- Push Neo4j cluster metrics to Azure Monitor Metrics
- Create custom metrics for cluster health indicators
- Configure metric-based alerts
- Build Azure Monitor Workbooks for cluster visualization

**Dashboard Requirements:**
- Cluster topology visualization showing all members
- Real-time cluster health status
- Replication lag trends
- Performance metrics over time
- Resource utilization per member

##### R4.4: Alert Rules Configuration

Define alert rules for critical cluster health conditions with appropriate severity levels.

**Critical Alerts (Severity 0 - Immediate Action):**
- Cluster quorum lost
- All cluster members offline
- Primary server unavailable with no automatic failover
- Backup failure for 24 hours
- Persistent volume full (100% capacity)

**High Severity Alerts (Severity 1 - Urgent):**
- Single cluster member offline for 15 minutes
- Replication lag exceeds 30 seconds
- Memory utilization above 90%
- TLS certificate expiring within 7 days
- Backup duration exceeding SLA threshold

**Medium Severity Alerts (Severity 2 - Investigation Required):**
- Replication lag exceeds 10 seconds
- CPU utilization above 80%
- Disk utilization above 85%
- Slow queries detected (execution time > 5 seconds)
- Backup verification failure

**Low Severity Alerts (Severity 3 - Informational):**
- Cluster scaling events
- Configuration changes applied
- Leader election completed successfully
- Backup completed successfully but with warnings

##### R4.5: Automated Backup Configuration

Implement automated backup strategy using Kubernetes CronJobs and Azure Blob Storage.

**Backup CronJob Requirements:**
- Schedule: Daily full backup at 2 AM UTC (configurable)
- Target: Execute backup from secondary server to minimize primary load
- Destination: Azure Blob Storage container with lifecycle policies
- Retention: Configurable (default 7 daily, 4 weekly, 12 monthly)

**Backup Process:**
1. CronJob creates backup pod with Azure Blob Storage credentials
2. Backup pod connects to secondary cluster member
3. Neo4j backup protocol streams backup to pod temporary storage
4. Backup is compressed and encrypted
5. Backup is uploaded to Azure Blob Storage with metadata
6. Temporary storage is cleaned up
7. Backup metadata is recorded for tracking

**Backup Metadata:**
- Backup timestamp
- Neo4j version
- Cluster size and member identities
- Database size
- Backup duration
- Backup verification status

##### R4.6: Backup Storage Configuration

Configure Azure Blob Storage for backup retention with appropriate redundancy and lifecycle policies.

**Storage Account Configuration:**
- Account Type: StorageV2 (general purpose v2)
- Redundancy: Geo-redundant storage (GRS) for disaster recovery
- Performance: Standard (sufficient for backup workloads)
- Access Tier: Cool (optimized for infrequent access)

**Container Configuration:**
- Container name: neo4j-backups-{deployment-id}
- Public access: None (private container)
- Soft delete: Enabled with 14-day retention
- Versioning: Enabled for backup file protection

**Lifecycle Management:**
- Move backups older than 30 days to Archive tier
- Delete backups older than 365 days (configurable)
- Exception: Keep monthly backups for 7 years

##### R4.7: Backup Verification

Implement automated backup verification to ensure backups are restorable.

**Verification Schedule:**
- Weekly verification of most recent full backup
- Verification runs in isolated AKS namespace
- Verification results recorded and alerted on failures

**Verification Process:**
1. Weekly CronJob triggers verification
2. Verification pod downloads recent backup from Azure Blob Storage
3. Temporary Neo4j instance is created in verification namespace
4. Backup is restored to temporary instance
5. Automated tests verify database accessibility and data integrity
6. Test creates sample queries and validates results
7. Temporary instance is terminated and cleaned up
8. Verification results are logged and alerted if failures occur

**Verification Metrics:**
- Restore duration
- Database size after restore
- Sample query success rate
- Data integrity check results

##### R4.8: Restore Procedures Documentation

Document comprehensive restore procedures for various disaster recovery scenarios.

**Single-Member Restore Procedure:**
Runbook for restoring one cluster member when others remain operational.

Steps:
1. Identify failed member and root cause
2. Remove member from cluster using DBMS procedure
3. Delete failed pod and PersistentVolumeClaim
4. Create new PVC from backup or allow fresh PVC creation
5. Restore backup to new PVC if required
6. Recreate pod which joins cluster automatically
7. Monitor synchronization with cluster
8. Validate member rejoins successfully

**Full-Cluster Restore Procedure:**
Runbook for complete cluster recovery after catastrophic failure.

Steps:
1. Deploy fresh AKS cluster and Neo4j infrastructure
2. Download most recent backup from Azure Blob Storage
3. Restore backup to first cluster member (neo4j-0)
4. Start first member in standalone mode for validation
5. Verify data integrity through sample queries
6. Scale StatefulSet to full cluster size
7. Additional members synchronize from first member
8. Validate cluster formation and quorum
9. Switch from standalone to cluster mode
10. Validate client connectivity and cluster operations

##### R4.9: TLS Encryption for Client Connections

Implement TLS encryption for client connections (Bolt and HTTPS) with certificate management.

**Certificate Requirements:**
- Support for both self-signed certificates (development) and CA-signed certificates (production)
- Certificate storage in Kubernetes Secrets or Azure Key Vault
- Certificate rotation without cluster downtime
- Separate certificates for Bolt and HTTPS if required

**TLS Configuration:**
- Enable Bolt TLS on port 7687 (bolt+tls://...)
- Enable HTTPS on port 7473
- Disable or redirect unencrypted HTTP (port 7474)
- Configure appropriate TLS versions (TLS 1.2+)
- Configure strong cipher suites

**Certificate Management:**
- Integration with cert-manager for automatic certificate generation and renewal
- Integration with Azure Key Vault for production certificate storage
- Documented procedure for manual certificate updates
- Certificate expiration monitoring and alerting

##### R4.10: TLS Encryption for Cluster Communication

Implement TLS encryption for inter-cluster communication including discovery, Raft protocol, and replication traffic.

**Cluster TLS Configuration:**
- Enable TLS for discovery protocol on port 6000
- Configure cluster member certificates (may use same cert as client TLS)
- Mutual TLS authentication between cluster members
- Certificate validation to prevent unauthorized members

**Certificate Distribution:**
Each cluster member needs:
- Its own certificate and private key
- CA certificate to validate peer certificates
- Appropriate certificate subject alternative names (SANs) including pod DNS names

**Security Implications:**
TLS cluster communication prevents:
- Eavesdropping on cluster replication traffic
- Man-in-the-middle attacks on cluster communication
- Unauthorized nodes joining the cluster

##### R4.11: Secrets Management with Azure Key Vault

Integrate Azure Key Vault for secure storage of sensitive configuration including passwords, certificates, and license keys.

**Key Vault Integration:**
- Use Azure Workload Identity for authentication
- Store Neo4j admin password in Key Vault
- Store TLS certificates and private keys in Key Vault
- Store plugin license keys in Key Vault
- Reference Key Vault secrets in pod configuration

**Secrets CSI Driver:**
Deploy Azure Key Vault Provider for Secrets Store CSI Driver:
- Install CSI driver in AKS cluster
- Create SecretProviderClass for Neo4j secrets
- Mount secrets into Neo4j pods as files
- Automatic secret rotation when Key Vault values change

**Secret Rotation:**
- Support rotating Neo4j password through Key Vault update
- Support rotating TLS certificates through Key Vault update
- Pods automatically receive updated secrets via CSI driver
- Neo4j configuration reloads secrets without pod restart

##### R4.12: Network Policies for Cluster Isolation

Implement Kubernetes Network Policies to restrict traffic to Neo4j cluster pods.

**Ingress Rules:**
- Allow traffic to Bolt port (7687) from application namespaces
- Allow traffic to HTTP/HTTPS ports (7474/7473) from ingress controllers
- Allow traffic to discovery port (6000) from other Neo4j cluster members
- Allow traffic to metrics port (2004) from Prometheus
- Deny all other ingress traffic by default

**Egress Rules:**
- Allow traffic to Kubernetes DNS (kube-dns)
- Allow traffic to Kubernetes API server (for K8S resolver)
- Allow traffic to Azure Blob Storage (for backups)
- Allow traffic to other Neo4j cluster members
- Deny all other egress traffic by default

**Policy Validation:**
Test network policies to ensure:
- Legitimate traffic is allowed
- Unauthorized traffic is blocked
- Cluster communication functions correctly
- Backups can reach Azure storage
- Metrics collection works

#### Phase 4 Todo List

1. **Enable Neo4j Prometheus metrics endpoint** - Configure Neo4j to expose metrics on port 2004 with appropriate metrics namespaces and labels

2. **Create Prometheus ServiceMonitor** - Define ServiceMonitor resource for automated scraping of Neo4j metrics by Prometheus

3. **Configure Container Insights for Neo4j namespace** - Enable Azure Monitor Container Insights for Neo4j pods and configure log collection

4. **Create Azure Monitor Workbook for cluster health** - Build custom workbook visualizing cluster topology, member status, and replication metrics

5. **Define alert rules for cluster health** - Create alert rules in Azure Monitor for critical conditions (quorum loss, member offline, replication lag)

6. **Create backup CronJob specification** - Define CronJob that executes Neo4j backup from secondary server and uploads to Azure Blob Storage

7. **Configure Azure Blob Storage for backups** - Create storage account and container with geo-redundant storage and lifecycle policies

8. **Implement backup authentication** - Configure backup pod to authenticate to Azure Blob Storage using workload identity or storage keys

9. **Create backup verification CronJob** - Define CronJob that downloads and restores backup to temporary instance for validation

10. **Document single-member restore procedure** - Create runbook with step-by-step instructions for restoring one cluster member

11. **Document full-cluster restore procedure** - Create runbook with step-by-step instructions for complete disaster recovery

12. **Generate or configure TLS certificates for client connections** - Set up cert-manager or manual certificates for Bolt and HTTPS endpoints

13. **Enable Bolt TLS in Neo4j configuration** - Configure Neo4j to require TLS for Bolt connections on port 7687

14. **Enable HTTPS in Neo4j configuration** - Configure Neo4j to serve HTTPS on port 7473 with TLS certificates

15. **Generate or configure TLS certificates for cluster communication** - Create certificates for inter-cluster TLS with appropriate SANs for pod DNS names

16. **Enable cluster TLS in Neo4j configuration** - Configure TLS for discovery and Raft protocol on port 6000

17. **Deploy Azure Key Vault Secrets CSI Driver** - Install CSI driver in AKS cluster for Key Vault integration

18. **Create SecretProviderClass for Neo4j secrets** - Define SecretProviderClass mapping Key Vault secrets to pod volumes

19. **Store secrets in Azure Key Vault** - Upload Neo4j password, TLS certificates, and license keys to Key Vault

20. **Mount Key Vault secrets in Neo4j pods** - Configure StatefulSet to mount SecretProviderClass volumes and reference secrets

21. **Create Network Policies for cluster isolation** - Define ingress and egress rules restricting traffic to necessary ports and sources

22. **Create monitoring validation tests** - Add test cases verifying metrics are exposed, collected, and queryable in Azure Monitor

23. **Create backup validation tests** - Add test cases that execute backup, verify storage upload, and test restore procedures

24. **Create TLS validation tests** - Add test cases that verify Bolt TLS connections and HTTPS endpoints work correctly

25. **Create cluster communication TLS tests** - Add test cases that verify inter-cluster communication uses TLS encryption

26. **Create security validation tests** - Add test cases that verify secrets are loaded from Key Vault and network policies enforce restrictions

27. **Update operations documentation** - Document monitoring setup, backup procedures, restore runbooks, certificate management, and security configuration

28. **Perform code review and testing** - Conduct comprehensive code review of monitoring, backup, and security implementations, execute validation tests for each component, verify backups are created and uploadable, test restore procedures in isolated environment, validate TLS connections work correctly, confirm Key Vault integration functions, test network policies enforce restrictions, and validate alert rules trigger appropriately

---

### Phase 5: Scalability and Validation - Dynamic Scaling and Comprehensive Testing

**Duration:** 2 weeks

**Objective:** Implement dynamic cluster scaling capabilities and extend the validation framework with comprehensive cluster-specific test scenarios covering all deployment configurations and failure modes.

**Prerequisites:**
- All previous phases completed and validated
- Monitoring and backup operational
- TLS and security configured

#### Requirements

##### R5.1: Automatic Cluster Member Enablement

Configure automatic enablement of new cluster members when scaling up to eliminate manual administrative steps.

**Configuration Requirement:**
When deploying clusters (nodeCount >= 3), configure Neo4j to automatically enable new servers when they join the cluster through the dbms.cluster.new_member.enabled setting.

**Behavior:**
- Default for standalone (nodeCount=1): Not applicable
- Default for cluster (nodeCount>=3): Automatic enablement enabled
- New members join and enable themselves without admin intervention
- Supports elastic scaling in response to load

**Considerations:**
Some organizations may prefer explicit administrative control over when new capacity becomes active. Support configurable enablement through parameter for those scenarios.

##### R5.2: Horizontal Pod Autoscaling Integration

Provide guidance and configuration examples for Kubernetes Horizontal Pod Autoscaler (HPA) integration with Neo4j clusters.

**Note on Direct HPA Support:**
Neo4j clusters have minimum size requirements (3 nodes for quorum) and cluster membership changes require coordination. Direct HPA is not recommended for core cluster members but may be suitable for read replicas in future enhancements.

**Documentation Requirements:**
- Document considerations for autoscaling Neo4j clusters
- Explain quorum requirements and minimum cluster sizes
- Provide manual scaling procedures as alternative
- Document future read replica autoscaling possibilities

##### R5.3: Scaling Operations Documentation

Document procedures for scaling cluster up and down with appropriate safeguards and validation steps.

**Scale-Up Procedure:**
1. Verify current cluster health (all members online and in quorum)
2. Update nodeCount parameter in deployment
3. Apply updated configuration (triggers StatefulSet scaling)
4. Monitor new pod startup and cluster join process
5. Verify new member reaches online state
6. Validate cluster quorum includes new member
7. Verify replication to new member
8. Update monitoring dashboards to include new member

**Scale-Down Procedure:**
1. Verify target cluster size maintains quorum (must have at least 3 members)
2. Identify member to remove (highest ordinal by convention)
3. Disable member through Cypher command (optional, automatic with modern Neo4j)
4. Update nodeCount parameter in deployment
5. Apply updated configuration
6. Monitor member removal and cluster rebalancing
7. Verify remaining members maintain quorum
8. Verify cluster operations continue normally
9. Clean up PersistentVolumeClaim if member will not return (manual step)

**Safety Requirements:**
- Prevent scaling below minimum quorum size (3 members)
- Require explicit confirmation for scale-down operations
- Automated validation that cluster is healthy before scaling
- Rollback capability if scaling operation fails

##### R5.4: Read Replica Support (Future Enhancement)

Document architecture for read replica deployment as future enhancement to clustering capabilities.

**Read Replica Architecture:**
- Read replicas are separate StatefulSet from core cluster
- Read replicas connect to core cluster for data replication
- Read replicas handle read-only queries to offload core cluster
- Read replicas can scale independently of core cluster
- Read replicas are better candidates for HPA than core members

**Implementation Planning:**
- Document read replica configuration requirements
- Describe service architecture for routing read queries
- Plan integration with load balancers
- Identify Helm chart changes required
- Estimate implementation timeline as separate phase

##### R5.5: Validation Framework Enhancement - Cluster Deployment Tests

Extend deployments/ validation framework with cluster-specific deployment test scenarios.

**Test Scenarios:**

**Standalone Deployment Test:**
- Deploy single-node Neo4j (nodeCount=1)
- Validate standalone mode configuration
- Verify data persistence
- Confirm external access via LoadBalancer
- Test backup and restore
- Validate monitoring metrics

**3-Node Cluster Deployment Test:**
- Deploy 3-node cluster (nodeCount=3)
- Validate cluster formation and quorum
- Verify all members reach online state
- Confirm cluster discovery mechanism (K8S resolver)
- Test replication across all members
- Validate external access routes to cluster
- Verify monitoring shows all members

**5-Node Cluster Deployment Test:**
- Deploy 5-node cluster (nodeCount=5)
- Validate cluster formation with larger quorum
- Verify replication across all members
- Test load distribution for read queries
- Validate pod distribution across nodes and zones

**Multi-Zone Cluster Test:**
- Deploy cluster in multi-zone AKS configuration
- Verify pod anti-affinity distributes across zones
- Validate cluster operates across zone boundaries
- Test zone failure resilience (if possible in test environment)

##### R5.6: Validation Framework Enhancement - Cluster Operations Tests

Add tests for cluster operational scenarios including scaling, failure, and recovery.

**Test Scenarios:**

**Cluster Scale-Up Test:**
- Deploy 3-node cluster
- Scale to 5 nodes
- Verify new members join automatically
- Confirm replication to new members
- Validate cluster operations during scaling

**Cluster Scale-Down Test:**
- Deploy 5-node cluster
- Scale down to 3 nodes
- Verify members are removed gracefully
- Confirm cluster maintains quorum throughout
- Validate cluster operations after scaling

**Single-Member Failure Test:**
- Deploy 3-node cluster
- Simulate member failure (delete pod)
- Verify cluster maintains quorum with 2 members
- Confirm read and write operations continue
- Validate automatic pod restart and cluster rejoin
- Verify data synchronization after rejoin

**Leader Failover Test:**
- Deploy 3-node cluster
- Identify current leader
- Simulate leader failure (delete leader pod)
- Verify leader election occurs
- Measure failover duration
- Confirm cluster operations resume with new leader

**Backup and Restore Test:**
- Deploy cluster and create test data
- Execute backup
- Verify backup uploaded to Azure Blob Storage
- Simulate cluster failure
- Restore from backup
- Validate data integrity after restore

**TLS Connection Test:**
- Deploy cluster with TLS enabled
- Test Bolt connection with TLS (bolt+tls:// URI)
- Test HTTPS connection
- Verify unencrypted connections are rejected
- Test certificate validation

##### R5.7: Validation Framework Enhancement - Performance Tests

Add performance benchmarking tests to validate cluster scaling benefits.

**Test Scenarios:**

**Write Performance Test:**
- Deploy 3-node cluster
- Execute write workload and measure throughput
- Validate write performance meets baseline expectations
- Measure write latency distribution

**Read Performance Scaling Test:**
- Deploy 3-node cluster
- Execute read workload and measure throughput
- Scale to 5 nodes
- Re-execute same read workload
- Verify read throughput improves proportionally
- Measure performance scaling efficiency

**Replication Lag Test:**
- Deploy cluster and execute write workload
- Measure replication lag to secondary servers
- Verify lag remains below acceptable threshold (< 1 second)
- Test under various load conditions

##### R5.8: Validation Framework Enhancement - Security Tests

Add security-focused tests to validate hardening implementations.

**Test Scenarios:**

**Network Policy Test:**
- Deploy cluster with network policies
- Attempt unauthorized connection to discovery port
- Verify connection is blocked by network policy
- Attempt authorized connection from another Neo4j pod
- Verify authorized connection succeeds

**Secrets Management Test:**
- Deploy cluster with Key Vault integration
- Verify Neo4j password is loaded from Key Vault
- Verify TLS certificates are loaded from Key Vault
- Test authentication using Key Vault-stored password
- Validate secrets are not visible in clear text in pod specs

**RBAC Validation Test:**
- Deploy cluster with K8S resolver
- Verify ServiceAccount has minimal required permissions
- Attempt to list services from Neo4j pod
- Verify permission is granted
- Attempt unauthorized operation (e.g., create services)
- Verify permission is denied

##### R5.9: Validation Framework Integration with CI/CD

Integrate cluster validation tests into GitHub Actions workflow for automated testing on pull requests.

**Workflow Requirements:**
- Trigger on pull requests affecting AKS marketplace templates
- Create temporary AKS cluster for testing
- Execute full test suite including cluster deployment and operations
- Clean up resources after testing
- Report test results in pull request

**Test Scenarios in CI/CD:**
- Standalone deployment
- 3-node cluster deployment
- Cluster scale-up operation
- Single-member failure and recovery
- Backup and restore
- TLS validation

**Resource Management:**
- Automated creation of test resource groups
- Automated cleanup after tests complete
- Cost control through smaller VM sizes in tests
- Timeout limits to prevent runaway costs

##### R5.10: Comprehensive Documentation

Create comprehensive documentation covering all cluster features, operations, and troubleshooting.

**Documentation Structure:**

**Architecture Documentation:**
- Cluster architecture overview with diagrams
- Service discovery mechanisms (LIST, SRV, K8S)
- Network architecture and port mappings
- Storage architecture and persistence model
- High availability and failover mechanisms

**Operations Documentation:**
- Deployment procedures for various cluster sizes
- Scaling procedures (up and down)
- Backup and restore runbooks
- Certificate management procedures
- Monitoring setup and dashboard usage
- Troubleshooting guides for common issues

**Security Documentation:**
- TLS configuration and certificate management
- Key Vault integration setup
- Network policy configuration
- RBAC setup and permissions
- Security best practices and compliance considerations

**Reference Documentation:**
- Complete parameter reference for all Bicep parameters
- Helm chart values reference
- Neo4j configuration reference
- Azure resource requirements and sizing guidance
- Cost estimation for various configurations

#### Phase 5 Todo List

1. **Configure automatic cluster member enablement** - Set Neo4j configuration to automatically enable new members joining cluster for elastic scaling support

2. **Document horizontal scaling considerations** - Create documentation explaining quorum requirements, minimum cluster sizes, and scaling best practices

3. **Create scale-up procedure documentation** - Write detailed runbook for adding cluster members with validation steps

4. **Create scale-down procedure documentation** - Write detailed runbook for removing cluster members safely while maintaining quorum

5. **Document read replica architecture** - Create architectural design document for future read replica implementation

6. **Implement standalone deployment test** - Add validation test for single-node deployment to deployments/ framework

7. **Implement 3-node cluster deployment test** - Add validation test for basic cluster deployment with quorum validation

8. **Implement 5-node cluster deployment test** - Add validation test for larger cluster to verify scaling capabilities

9. **Implement multi-zone cluster test** - Add validation test that verifies pod distribution across availability zones

10. **Implement cluster scale-up test** - Add operational test that scales cluster from 3 to 5 nodes and validates new member integration

11. **Implement cluster scale-down test** - Add operational test that scales cluster from 5 to 3 nodes and validates graceful removal

12. **Implement single-member failure test** - Add resilience test that simulates pod failure and validates cluster recovery

13. **Implement leader failover test** - Add resilience test that triggers leader election and measures failover duration

14. **Implement backup and restore test** - Add operational test that validates complete backup and restore workflow

15. **Implement TLS connection test** - Add security test that validates TLS connections and certificate validation

16. **Implement write performance test** - Add performance test measuring write throughput and latency

17. **Implement read performance scaling test** - Add performance test measuring read performance improvement with cluster size

18. **Implement replication lag test** - Add performance test measuring replication lag under load

19. **Implement network policy test** - Add security test validating network policy enforcement

20. **Implement secrets management test** - Add security test validating Key Vault integration and secret loading

21. **Implement RBAC validation test** - Add security test validating ServiceAccount permissions for K8S resolver

22. **Integrate tests into GitHub Actions workflow** - Update CI/CD workflow to execute cluster validation tests on pull requests

23. **Create cluster architecture documentation** - Write comprehensive architecture document with diagrams and explanations

24. **Create cluster operations documentation** - Write operations runbooks for deployment, scaling, backup, and maintenance

25. **Create security documentation** - Write security guide covering TLS, Key Vault, network policies, and best practices

26. **Create parameter reference documentation** - Document all Bicep and Helm parameters with descriptions and valid values

27. **Create troubleshooting guide** - Document common issues, symptoms, diagnostics, and resolutions

28. **Perform code review and testing** - Conduct comprehensive code review of all Phase 5 implementations, execute complete validation test suite across all scenarios, verify all tests pass consistently, measure performance baselines, validate documentation accuracy and completeness, test deployment across different AKS configurations, and confirm all acceptance criteria are met

---

## Success Metrics and Validation

### Deployment Success Metrics

**Cluster Formation Success Rate:**
- Target: 99%+ successful cluster formation across test scenarios
- Measurement: Automated tests execute cluster deployment and verify quorum
- Validation: All cluster members reach online state within 5 minutes

**Deployment Consistency:**
- Target: Identical deployments produce identical cluster configurations
- Measurement: Deploy same configuration multiple times and compare cluster state
- Validation: Configuration checksums match across deployments

### Operational Success Metrics

**High Availability:**
- Target: Cluster maintains availability during single-node failures
- Measurement: Simulate pod failures and measure service interruption duration
- Validation: Read and write operations continue within 30 seconds of failure

**Backup Reliability:**
- Target: 100% backup success rate over 30-day observation period
- Measurement: Monitor backup job executions and success/failure rates
- Validation: All scheduled backups complete successfully and are verified

**Restore Capability:**
- Target: Successful restore from backup in under 30 minutes for 100GB database
- Measurement: Time restore procedures during testing
- Validation: Restored data matches original data with 100% fidelity

### Performance Success Metrics

**Read Scaling Efficiency:**
- Target: 80%+ read throughput improvement when scaling from 3 to 5 nodes
- Measurement: Execute identical read workload on 3-node and 5-node clusters
- Validation: 5-node cluster throughput is at least 1.8x the 3-node cluster throughput

**Replication Lag:**
- Target: Replication lag below 1 second under normal load conditions
- Measurement: Monitor replication lag metrics during standard workload
- Validation: 95th percentile replication lag < 1 second

**Failover Duration:**
- Target: Leader election completes within 30 seconds
- Measurement: Simulate leader failure and measure time until new leader elected
- Validation: Cluster operations resume within 30 seconds

### Security Success Metrics

**TLS Adoption:**
- Target: 100% of client connections use TLS encryption in production deployments
- Measurement: Monitor connection protocols via metrics
- Validation: No unencrypted Bolt connections accepted

**Secrets Protection:**
- Target: Zero secrets exposed in clear text in Kubernetes resources
- Measurement: Audit pod specs, config maps, and deployment templates
- Validation: All sensitive values referenced from Key Vault or Secrets

**Network Isolation:**
- Target: 100% of unauthorized network traffic blocked by network policies
- Measurement: Attempt unauthorized connections from test pods
- Validation: All unauthorized connection attempts are blocked

### Documentation Success Metrics

**Documentation Completeness:**
- Target: All operational procedures documented with runbooks
- Measurement: Checklist of required documentation topics
- Validation: Operations team can execute all procedures following documentation alone

**Documentation Accuracy:**
- Target: Zero errors in documented procedures when executed
- Measurement: Execute each documented procedure and record errors
- Validation: All procedures execute successfully without corrections needed

---

## Risk Assessment and Mitigation

### Technical Risks

**Risk T1: Cluster Formation Failures**

**Description:** Cluster members fail to discover each other or form quorum due to network, DNS, or configuration issues.

**Probability:** Medium
**Impact:** High (deployment fails to achieve operational state)

**Mitigation Strategies:**
- Implement multiple resolver types (LIST, SRV, K8S) with fallback options
- Add pre-deployment validation that verifies network connectivity
- Include init containers that validate DNS resolution before starting Neo4j
- Provide detailed troubleshooting documentation for discovery issues
- Add cluster formation timeout with clear error messages
- Implement automated testing across diverse AKS network configurations

**Risk T2: Data Loss During Scaling Operations**

**Description:** Scaling cluster down or removing members could result in data loss if proper safeguards are not in place.

**Probability:** Low
**Impact:** Critical (permanent data loss)

**Mitigation Strategies:**
- Enforce minimum cluster size (3 members) to maintain quorum
- Require explicit administrative confirmation for scale-down operations
- Implement pre-scaling validation that verifies cluster health
- Document PersistentVolumeClaim retention policies clearly
- Automate backup before scaling operations
- Test scale-down procedures extensively in non-production environments
- Provide clear warnings about data retention when scaling down

**Risk T3: Performance Degradation Under Load**

**Description:** Cluster performance may degrade under high load due to replication overhead, network saturation, or resource contention.

**Probability:** Medium
**Impact:** High (service degradation affects users)

**Mitigation Strategies:**
- Establish performance baselines through load testing
- Monitor replication lag and alert when thresholds exceeded
- Size AKS nodes appropriately for Neo4j workload requirements
- Document performance tuning guidance for various workload patterns
- Implement resource quotas and limits to prevent resource exhaustion
- Test under realistic production load conditions
- Provide scaling guidance based on performance metrics

**Risk T4: Certificate Management Complexity**

**Description:** TLS certificate generation, distribution, and rotation could introduce complexity leading to service interruptions or security gaps.

**Probability:** Medium
**Impact:** Medium (service interruption or security vulnerability)

**Mitigation Strategies:**
- Support both simple self-signed certificates (development) and CA-signed certificates (production)
- Integrate with cert-manager for automated certificate lifecycle management
- Implement certificate expiration monitoring with advance warning
- Document certificate rotation procedures with zero-downtime approach
- Test certificate rotation in non-production environments
- Provide fallback to non-TLS for troubleshooting (development only)
- Include certificate validation in deployment tests

### Operational Risks

**Risk O1: Backup Failures Go Unnoticed**

**Description:** Automated backups may fail silently due to configuration issues, credential expiration, or storage problems, leaving no viable recovery option.

**Probability:** Medium
**Impact:** Critical (data loss if cluster failure occurs)

**Mitigation Strategies:**
- Implement backup monitoring with immediate alerts on failures
- Weekly automated backup verification through restore testing
- Monitor backup size and duration trends to detect anomalies
- Test restore procedures regularly (monthly minimum)
- Implement multiple backup retention locations for redundancy
- Require manual confirmation that backups are operational after deployment
- Include backup validation in deployment acceptance tests

**Risk O2: Inadequate Monitoring Leads to Undetected Issues**

**Description:** Cluster health issues may go undetected until they cause service impact due to insufficient monitoring coverage or alert fatigue.

**Probability:** Medium
**Impact:** High (service degradation or outage)

**Mitigation Strategies:**
- Implement comprehensive monitoring covering all critical health indicators
- Tune alert thresholds to minimize false positives while catching real issues
- Create tiered alerting with appropriate severity levels
- Provide runbooks for each alert to guide response
- Dashboard visualization enables proactive issue detection
- Regular review of monitoring effectiveness and alert quality
- Include monitoring validation in deployment tests

**Risk O3: Operational Complexity Exceeds Team Capabilities**

**Description:** The enhanced clustering features introduce operational complexity that exceeds the capabilities of teams managing the deployment.

**Probability:** Low
**Impact:** High (operational errors lead to service issues)

**Mitigation Strategies:**
- Provide comprehensive documentation covering all operational procedures
- Create runbooks for common operational tasks with step-by-step instructions
- Offer training materials or workshops for operations teams
- Design for operational simplicity with sensible defaults
- Implement guardrails that prevent dangerous operations
- Provide clear error messages that guide resolution
- Make Neo4j consulting and support available for complex scenarios

### Schedule Risks

**Risk S1: Implementation Timeline Overruns**

**Description:** Implementation phases take longer than estimated due to technical challenges, resource constraints, or scope creep.

**Probability:** Medium
**Impact:** Medium (delayed feature availability)

**Mitigation Strategies:**
- Include buffer time in each phase for unexpected challenges
- Prioritize features by criticality, implementing must-haves first
- Use phased approach enabling early delivery of core functionality
- Regular progress reviews to identify delays early
- Maintain flexibility to adjust scope if needed
- Clear phase boundaries enable independent delivery
- Stakeholder communication about realistic timelines

**Risk S2: Dependency on External Components**

**Description:** Implementation depends on external components (Azure services, Helm charts, Neo4j versions) that may change or encounter issues.

**Probability:** Low
**Impact:** Medium (blocked implementation or rework required)

**Mitigation Strategies:**
- Pin Neo4j Helm chart version to tested release
- Document tested Azure service versions and configurations
- Monitor for breaking changes in dependencies
- Maintain relationships with Neo4j and Azure support for early warning
- Include fallback options where possible
- Test with multiple versions of dependencies when feasible

---

## Rollback and Recovery Procedures

### Phase Rollback Strategy

Each implementation phase includes rollback procedures to revert to previous stable state if critical issues are discovered.

**Rollback Triggers:**
- Critical bugs discovered during phase validation
- Performance degradation beyond acceptable thresholds
- Security vulnerabilities introduced
- Deployment reliability below 90% success rate

**Rollback Procedure:**
1. Stop new deployments using phase implementation
2. Document issues encountered and root cause analysis
3. Revert Bicep and Helm chart changes to previous phase
4. Re-deploy test environments with reverted configuration
5. Validate rolled-back configuration works correctly
6. Address root cause issues before re-attempting phase
7. Communicate rollback to stakeholders

### Production Deployment Rollback

For production clusters already deployed with enhanced clustering, rollback procedures depend on the specific component.

**Service Discovery Rollback (K8S → SRV → LIST):**
If K8S resolver encounters issues, revert to SRV or LIST resolver:
1. Identify resolver-related issues through logs and monitoring
2. Update Neo4j configuration to previous resolver type
3. Perform rolling restart of cluster pods with updated configuration
4. Monitor cluster reformation with previous resolver
5. Validate cluster operations return to normal

**TLS Rollback (Encrypted → Unencrypted):**
If TLS introduces connectivity issues (development/testing only):
1. Update Neo4j configuration to disable TLS requirements
2. Perform rolling restart of cluster pods
3. Validate client connectivity without TLS
4. Address TLS configuration issues
5. Re-enable TLS after fixes applied

**Note:** TLS rollback should never be used in production environments. Address TLS issues while maintaining encryption.

---

## Appendix: Technical Reference

### A. Kubernetes Resources Created

**Per Deployment:**
- 1x Namespace (neo4j)
- 1x ServiceAccount (neo4j-sa)
- 1x Role (neo4j-service-reader)
- 1x RoleBinding (neo4j-service-reader-binding)
- 1x StorageClass (neo4j-premium)
- 1x StatefulSet (neo4j, with N replicas)
- Nx PersistentVolumeClaim (one per StatefulSet replica)
- 1x Headless Service (neo4j-headless)
- 1x LoadBalancer Service (neo4j-lb)
- 1x ConfigMap (neo4j-config)
- 1x Secret (neo4j-secrets)
- 1x ServiceMonitor (neo4j-metrics, if Prometheus enabled)
- 1x NetworkPolicy (neo4j-network-policy)
- 1x CronJob (neo4j-backup)
- 1x CronJob (neo4j-backup-verification)

### B. Azure Resources Created

**Per Deployment:**
- 1x Resource Group
- 1x AKS Cluster
- 1x Virtual Network
- 2x Subnets (system, user)
- 1x User-Assigned Managed Identity
- 1x Log Analytics Workspace
- 1x Public IP (for LoadBalancer)
- Nx Azure Disks (one per PVC)
- 1x Storage Account (for backups)
- 1x Blob Container (for backup retention)
- 1x Azure Key Vault (optional, for secrets)

### C. Neo4j Configuration Parameters

**Critical Configuration for Clustering:**

```
# Discovery Configuration
dbms.cluster.discovery.resolver_type=K8S
dbms.kubernetes.label_selector=app=neo4j,component=cluster
dbms.kubernetes.discovery.service_port_name=discovery

# Cluster Identity
server.cluster.advertised_address=<pod-dns-name>:6000
server.cluster.listen_address=0.0.0.0:6000

# Cluster Membership
neo4j.minimumClusterSize=3
dbms.cluster.new_member.enabled=true

# Memory Configuration
server.memory.heap.initial_size=4G
server.memory.heap.max_size=4G
server.memory.pagecache.size=3G

# TLS Configuration
server.bolt.tls_level=REQUIRED
server.https.enabled=true
dbms.ssl.policy.bolt.enabled=true
dbms.ssl.policy.cluster.enabled=true

# Metrics Configuration
server.metrics.enabled=true
server.metrics.prometheus.enabled=true
server.metrics.prometheus.endpoint=0.0.0.0:2004
```

### D. Port Reference

| Port | Protocol | Purpose | Exposure |
|------|----------|---------|----------|
| 6000 | TCP | Cluster discovery, Raft protocol | Internal (headless service) |
| 7687 | TCP | Bolt protocol (client connections) | External (LoadBalancer) |
| 7474 | TCP | HTTP (Neo4j Browser, API) | External (LoadBalancer) |
| 7473 | TCP | HTTPS (encrypted browser, API) | External (LoadBalancer) |
| 6362 | TCP | Backup protocol | Internal (for backup jobs) |
| 2004 | TCP | Prometheus metrics | Internal (for Prometheus) |

### E. Resource Requirements

**Minimum Requirements per Cluster Member:**
- CPU: 2 cores (2000m)
- Memory: 8 GiB
- Storage: 32 GiB Premium SSD
- Network: 1 Gbps

**Recommended Production Configuration:**
- CPU: 4-8 cores
- Memory: 16-32 GiB
- Storage: 128-512 GiB Premium SSD
- Network: 10 Gbps

**AKS Node Pool Sizing:**
For 3-node cluster with recommended configuration:
- System Node Pool: 3x Standard_D2s_v5 (2 vCPU, 8 GiB RAM)
- User Node Pool: 3x Standard_E8s_v5 (8 vCPU, 64 GiB RAM)

### F. Validation Test Matrix

| Test Category | Test Name | Deployment Config | Pass Criteria |
|---------------|-----------|-------------------|---------------|
| Deployment | Standalone | nodeCount=1 | Pod starts, database accessible |
| Deployment | 3-node cluster | nodeCount=3 | Cluster forms quorum, all online |
| Deployment | 5-node cluster | nodeCount=5 | Cluster forms quorum, all online |
| Deployment | Multi-zone | nodeCount=3, multi-zone AKS | Pods distributed across zones |
| Operations | Scale up | 3→5 nodes | New members join automatically |
| Operations | Scale down | 5→3 nodes | Members removed gracefully |
| Resilience | Single failure | Delete 1 pod | Cluster maintains operations |
| Resilience | Leader failover | Delete leader | New leader elected < 30s |
| Backup | Backup execution | Execute backup | Backup uploaded to storage |
| Backup | Restore | Restore from backup | Data matches original |
| Security | TLS connections | TLS enabled | bolt+tls:// works, bolt:// rejected |
| Security | Network policy | Policy enabled | Unauthorized traffic blocked |
| Security | Key Vault | KV integration | Secrets loaded from KV |
| Performance | Write throughput | Standard workload | Meets baseline TPS |
| Performance | Read scaling | 3 vs 5 nodes | 80%+ throughput improvement |
| Performance | Replication lag | Write workload | Lag < 1 second |

---

## Conclusion

This proposal provides a comprehensive roadmap for transforming the Neo4j Enterprise AKS deployment into a production-grade clustered database platform. The phased implementation approach balances risk management with incremental value delivery, ensuring each phase builds upon a stable foundation.

The enhanced clustering capabilities will enable enterprise customers to deploy Neo4j on Azure Kubernetes Service with confidence, knowing they have access to high availability, disaster recovery, comprehensive monitoring, and production-grade operational capabilities.

**Key Deliverables:**
- Cloud-native service discovery using Kubernetes-native mechanisms
- Production-grade high availability with automatic failover
- Comprehensive monitoring and alerting integrated with Azure Monitor
- Automated backup and documented restore procedures
- Security hardening with TLS encryption and Azure Key Vault integration
- Dynamic scaling capabilities for elastic workload adaptation
- Extensive validation framework ensuring deployment reliability
- Comprehensive documentation enabling operational excellence

**Timeline Summary:**
- Phase 1 (Foundation): 2 weeks
- Phase 2 (SRV Resolver): 2 weeks
- Phase 3 (K8S Resolver): 2 weeks
- Phase 4 (Operations): 3 weeks
- Phase 5 (Validation): 2 weeks
- **Total: 11 weeks** (including testing and documentation)

**Success Measurement:**
Success will be measured through automated validation tests, operational metrics, and customer feedback. The proposal defines clear success criteria for each phase, ensuring measurable progress toward production-ready clustering.

---

**Next Steps:**
1. Review and approval of proposal by stakeholders
2. Resource allocation for implementation team
3. Test environment provisioning
4. Phase 1 implementation kickoff
5. Regular progress reviews at phase boundaries

---

**Document History:**
- Version 1.0 - Initial proposal - November 20, 2025
