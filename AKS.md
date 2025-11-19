# Neo4j on Azure Kubernetes Service (AKS) - Deployment Proposal

## Executive Summary

This proposal outlines a plan to create a new Azure Marketplace offering for Neo4j Enterprise running on Azure Kubernetes Service (AKS). This will complement the existing Virtual Machine-based deployment by providing a modern, container-based alternative that aligns with Kubernetes-native deployment patterns and cloud-native best practices.

## Why AKS?

### Benefits Over VM-Based Deployments

**Operational Simplicity:**
- Automatic pod rescheduling if nodes fail
- Built-in health checks and self-healing
- Rolling updates without downtime
- Easier scaling up and down

**Cost Efficiency:**
- More efficient resource utilization through pod packing
- Ability to use spot instances for non-production workloads
- Autoscaling based on actual resource usage
- Smaller overhead compared to full VMs

**Cloud-Native Integration:**
- Native integration with Azure services (Key Vault, Monitor, Storage)
- Standard Kubernetes tooling and workflows
- Better CI/CD integration
- Consistent deployment patterns across cloud providers

**Developer Experience:**
- Familiar Kubernetes primitives for DevOps teams
- Declarative configuration via Helm charts
- Easy local development with Minikube/Kind
- Standard kubectl commands for troubleshooting

### Target Users

1. **Kubernetes-native organizations** already running applications on AKS
2. **DevOps teams** preferring container-based workflows
3. **Multi-cloud enterprises** wanting consistent deployment patterns
4. **Development teams** needing rapid environment provisioning
5. **Organizations** with existing Kubernetes expertise

## Current State vs. Proposed State

### Current VM-Based Approach

**What we have today:**
- Virtual Machine Scale Sets (VMSS) running Neo4j directly on Ubuntu VMs
- Cloud-init scripts for installation and configuration
- Azure Load Balancer for cluster access
- Individual VMs with public IPs for direct access
- Managed disks attached to each VM for data storage
- Cluster discovery via DNS and Azure API

**Deployment types:**
- Standalone: Single VM instance
- Cluster: 3-10 VMs in a cluster configuration
- Read Replicas: Additional VMs for read traffic (Neo4j 4.4 only)

### Proposed AKS-Based Approach

**What we will build:**
- AKS cluster with dedicated node pools for Neo4j workloads
- Neo4j running in StatefulSet pods (not directly on VMs)
- Kubernetes Services for load balancing and discovery
- Azure Disk-backed Persistent Volumes for data storage
- Helm charts for Neo4j configuration and deployment
- Kubernetes-native service discovery

**Deployment types:**
- Standalone: Single pod in a StatefulSet
- Cluster: StatefulSet with 3-10 replicas
- Analytics Cluster: Primary server with multiple secondaries for read-heavy workloads

**Key difference:** Instead of installing Neo4j directly on VMs, we provision an AKS cluster and deploy Neo4j as containerized workloads managed by Kubernetes.

## Architecture Overview

### Component Mapping: VM to AKS

**Infrastructure Layer:**

| VM Approach | AKS Approach | Purpose |
|-------------|--------------|---------|
| Virtual Network | Virtual Network | Network isolation |
| VMSS for Neo4j nodes | AKS Node Pool | Compute resources |
| Individual VMs | Kubernetes Pods | Neo4j instances |
| Azure Managed Disks | Persistent Volumes (PVs) | Data storage |
| Azure Load Balancer | Kubernetes LoadBalancer Service | External access |
| NSG Rules | Network Policies | Traffic control |
| Managed Identity | Workload Identity | Azure service auth |

**Configuration Layer:**

| VM Approach | AKS Approach | Purpose |
|-------------|--------------|---------|
| Cloud-init scripts | Helm chart templates | Neo4j setup |
| VM extensions | Init containers | Pre-start tasks |
| Environment variables | ConfigMaps | Configuration |
| Key Vault secrets | Key Vault CSI driver | Password management |
| DNS-based discovery | Kubernetes DNS | Cluster member discovery |

**Application Layer:**

| VM Approach | AKS Approach | Purpose |
|-------------|--------------|---------|
| Neo4j installed via yum | Neo4j Docker image | Application runtime |
| Systemd service | StatefulSet controller | Process management |
| VM hostnames | Pod DNS names | Instance identity |
| Direct IP access | ClusterIP/LoadBalancer | Network access |

### High-Level Architecture

**Standalone Deployment:**
1. User deploys Bicep template from Azure Portal
2. Bicep creates AKS cluster with single node pool
3. Bicep installs Helm chart for Neo4j standalone
4. StatefulSet creates one pod with Neo4j container
5. Persistent Volume provisioned from Azure Disk
6. LoadBalancer Service exposes Neo4j externally
7. User accesses Neo4j via public IP or DNS

**Cluster Deployment:**
1. User deploys Bicep template with nodeCount=3
2. Bicep creates AKS cluster with appropriately sized node pool
3. Bicep installs Helm chart for Neo4j cluster
4. StatefulSet creates 3 pods (neo4j-0, neo4j-1, neo4j-2)
5. Headless Service enables pod-to-pod discovery
6. Each pod gets Persistent Volume for data
7. LoadBalancer Service distributes traffic across pods
8. Pods discover each other via Kubernetes DNS
9. Neo4j cluster forms automatically
10. User accesses cluster via load balancer endpoint

### Data Flow

**Cluster Formation:**
1. Pod neo4j-0 starts and waits for cluster members
2. Pod neo4j-1 starts and discovers neo4j-0 via DNS
3. Pod neo4j-2 starts and discovers neo4j-0, neo4j-1
4. Pods elect leader via Raft consensus protocol
5. Cluster becomes ready for traffic

**Client Access:**
1. Client connects to LoadBalancer Service public IP
2. Service routes to healthy Neo4j pod
3. Neo4j driver performs routing (for cluster-aware clients)
4. Queries distributed based on transaction type (read/write)

**Data Persistence:**
1. Each pod has PersistentVolumeClaim
2. Azure Disk dynamically provisioned and attached
3. Neo4j data written to /data mount point
4. If pod restarts, same volume reattached
5. Data survives pod rescheduling and node failures

## Detailed Component Breakdown

### 1. AKS Cluster Module

**What it does:**
Creates the Kubernetes cluster that will host Neo4j workloads.

**Key configuration:**
- Kubernetes version (stable channel)
- System node pool for cluster services (small, 2-3 nodes)
- User node pool for Neo4j workloads (sized based on nodeCount)
- Network plugin (Azure CNI for integration)
- Monitoring enabled (Azure Monitor for containers)
- Workload Identity enabled for Key Vault access

**Why separate node pools:**
- System pool runs Kubernetes core services (DNS, metrics, etc.)
- User pool dedicated to Neo4j - can be scaled independently
- Prevents resource contention between cluster services and application

### 2. Storage Configuration

**What it does:**
Defines how Neo4j data is persisted across pod restarts.

**Storage approach:**
- StorageClass using Azure Disk (Premium SSD)
- PersistentVolumeClaim per pod (created by StatefulSet)
- Volume expansion enabled for future growth
- Retain policy (volumes persist even if pods deleted)

**Sizing:**
- Default: 32 GB per pod (matching current VM disk default)
- Configurable via parameter (diskSize)
- Can be expanded without data loss

### 3. Network Architecture

**Internal networking:**
- Headless Service for StatefulSet discovery (neo4j.namespace.svc.cluster.local)
- ClusterIP Service for internal cluster communication
- Each pod gets DNS name: neo4j-0.neo4j.namespace.svc.cluster.local

**External access:**
- LoadBalancer Service for external traffic
- Public IP provisioned in Azure
- DNS label for friendly hostname
- Health probes on ports 7474 (HTTP) and 7687 (Bolt)

**Security:**
- Network Policies to restrict pod-to-pod traffic
- NSG on AKS subnet for additional perimeter security
- TLS termination options (ingress or in-pod)

### 4. Identity and Secrets Management

**Workload Identity:**
- Replaces legacy pod identity mechanisms
- Managed identity attached to service account
- Pods assume identity via federated credentials
- Used for Key Vault access and Azure API calls

**Secrets approach:**
- Option 1: Kubernetes Secret for admin password
- Option 2: Azure Key Vault CSI driver for enterprise deployments
- Plugin license keys stored as secrets
- Mounted into pods as files or environment variables

### 5. Neo4j Deployment via Helm

**Why Helm:**
- Official Neo4j Helm charts maintained by Neo4j team
- Handles complexity of StatefulSet configuration
- Templating for different deployment sizes
- Version management and rollback capability

**What Helm chart configures:**
- StatefulSet with replica count
- Container image and version
- Resource requests and limits (CPU/memory)
- Volume claim templates
- Environment variables for Neo4j configuration
- Init containers for pre-start tasks
- Liveness and readiness probes

**Customization:**
- Pass parameters from Bicep to Helm values
- Neo4j configuration via ConfigMap
- Plugins installed via init containers
- License type set via environment variable

### 6. Cluster Discovery Mechanism

**How pods find each other:**
- Kubernetes provides stable DNS names for StatefulSet pods
- Pod neo4j-0 is always at neo4j-0.neo4j.svc.cluster.local
- Neo4j configured with discovery endpoints:
  - neo4j-0.neo4j:6000
  - neo4j-1.neo4j:6000
  - neo4j-2.neo4j:6000
- Pods communicate directly pod-to-pod (no load balancer for cluster traffic)
- Raft consensus runs over port 7000
- Transaction shipping over port 6000

**Comparison to VM approach:**
- VM: Discovers via DNS queries to Azure API and IP addresses
- AKS: Discovers via Kubernetes DNS (more reliable and faster)

### 7. Monitoring and Observability

**Built-in capabilities:**
- Azure Monitor for containers integration
- Container logs streamed to Log Analytics
- Metrics on pod CPU, memory, disk usage
- AKS cluster health monitoring

**Neo4j-specific:**
- Neo4j metrics endpoint (:2004/metrics)
- Prometheus scraping support
- Custom dashboards in Azure Monitor
- Query logs available via kubectl logs

### 8. Backup and Disaster Recovery

**Backup approaches:**
- Online backup to Azure Blob Storage
- Volume snapshots of Persistent Volumes
- Neo4j dump to external storage
- Cross-region replication for DR

**Restoration:**
- Restore from snapshot to new PV
- Load dump file into new deployment
- Clone PV from snapshot for fast recovery

## Deployment Scenarios

We will support the same core scenarios as VM deployments, adapted for Kubernetes:

### Scenario 1: Standalone Neo4j 5.x
- 1 pod in StatefulSet
- Single Persistent Volume
- LoadBalancer Service for external access
- Evaluation license
- Use case: Development, testing, small applications

### Scenario 2: Cluster Neo4j 5.x (3 nodes)
- 3 pods in StatefulSet
- 3 Persistent Volumes (one per pod)
- Headless Service for discovery
- LoadBalancer Service for client access
- Evaluation or Enterprise license
- Use case: Production workloads requiring HA

### Scenario 3: Cluster Neo4j 5.x (5 nodes)
- 5 pods in StatefulSet
- Higher availability than 3-node cluster
- Better read scalability
- Use case: High-traffic production applications

### Scenario 4: Analytics Cluster
- 1 primary + 2 secondary servers
- Optimized for read-heavy analytical queries
- Separate routing for analytics traffic
- Use case: Data science, business intelligence

### Scenario 5: Cluster with Graph Data Science
- 3-node cluster
- GDS plugin pre-installed
- License key configured
- Extra memory allocation for graph algorithms
- Use case: Graph analytics, machine learning

### Scenario 6: Cluster with Bloom
- 3-node cluster
- Bloom plugin pre-installed
- License key configured
- Additional service endpoint for Bloom UI
- Use case: Graph visualization, business users

### Scenario 7: Neo4j 4.4 Cluster (Legacy support)
- 3-node Neo4j 4.4 cluster
- For customers not yet ready to upgrade to 5.x
- Limited support timeline
- Use case: Migration period for existing 4.4 customers

## Implementation Phases

### Phase 1: Foundation (Weeks 1-2)

**Objective:** Set up basic infrastructure and single-node deployment

**Tasks:**

**Week 1: Infrastructure Setup**
- Create marketplace/neo4j-enterprise-aks directory structure
- Design Bicep module architecture for AKS
- Set up development and testing environment
- Research Neo4j official Helm charts and versions
- Document AKS-specific Azure requirements (quotas, permissions)
- Create initial parameters.json with AKS-specific parameters
- Design createUiDefinition.json for AKS deployment wizard

**Week 2: Basic AKS Module**
- Create network.bicep module for AKS virtual network
- Create identity.bicep module for Workload Identity setup
- Create aks-cluster.bicep module for cluster provisioning
  - Configure system node pool
  - Configure user node pool for Neo4j
  - Enable monitoring and logging
  - Set Kubernetes version
- Create storage.bicep module for StorageClass configuration
- Create main.bicep to orchestrate modules
- Test basic AKS cluster creation and deletion

**Deliverables:**
- Working AKS cluster that can be created via Bicep
- Clean resource group deletion
- No Neo4j deployment yet (just infrastructure)

**Todo list for Phase 1:**
- Research Neo4j Helm chart repository and latest stable versions
- Determine minimum AKS cluster size and node pool requirements
- Document Azure subscription requirements (quotas, service limits)
- Create directory structure matching existing neo4j-enterprise layout
- Write network.bicep for AKS-compatible virtual network
- Write identity.bicep for managed identity and Workload Identity federation
- Write aks-cluster.bicep with system and user node pools
- Write storage.bicep for Azure Disk StorageClass
- Write parameters.json with standalone test configuration
- Write main.bicep orchestrating all modules
- Create deploy.sh script for local testing
- Create delete.sh script for cleanup
- Test deployment to ensure clean creation and deletion
- Document any Azure permission requirements discovered

### Phase 2: Standalone Deployment (Weeks 3-4)

**Objective:** Deploy single-instance Neo4j on AKS

**Tasks:**

**Week 3: Helm Integration**
- Research Neo4j Helm chart configuration options
- Create helm-release.bicep module to deploy Helm charts from Bicep
- Map deployment parameters to Helm chart values
- Configure Neo4j 5.x standalone mode
- Set up admin password (Kubernetes Secret approach first)
- Configure Persistent Volume sizing
- Create LoadBalancer Service for external access

**Week 4: Validation and Testing**
- Deploy standalone instance end-to-end
- Test connectivity via Bolt protocol
- Test Neo4j Browser access via HTTP
- Verify data persistence across pod restarts
- Add aks-standalone-v5 scenario to deployments/config
- Extend validate_deploy to support AKS scenarios
- Run validation tests and fix issues
- Document deployment process

**Deliverables:**
- Working standalone Neo4j 5.x on AKS
- Automated validation passing
- User can access Neo4j Browser and run queries
- Data survives pod restarts

**Todo list for Phase 2:**
- Study Neo4j Helm chart values.yaml structure
- Determine best approach for Helm deployment from Bicep (Helm provider or kubectl)
- Create helm-release.bicep module or equivalent
- Map adminPassword parameter to Kubernetes Secret
- Map graphDatabaseVersion to Neo4j container image tag
- Map licenseType to Neo4j environment variable
- Map diskSize to PersistentVolumeClaim storage request
- Configure LoadBalancer Service for ports 7474 and 7687
- Test standalone deployment creates all resources
- Verify Neo4j pod starts successfully
- Verify PVC is bound and mounted
- Verify LoadBalancer gets public IP
- Test connection via neo4j:// protocol
- Test connection via HTTP browser
- Create test dataset and verify persistence after pod restart
- Add aks-standalone-v5 to scenarios.yaml
- Extend DeploymentEngine to handle AKS deployments
- Extend connection info extraction for Kubernetes Services
- Run validate_deploy aks-standalone-v5 successfully
- Document standalone deployment guide

### Phase 3: Cluster Deployment (Weeks 5-7)

**Objective:** Deploy multi-node Neo4j clusters on AKS

**Tasks:**

**Week 5: Cluster Configuration**
- Research Neo4j cluster requirements for Kubernetes
- Configure StatefulSet with multiple replicas
- Create Headless Service for cluster discovery
- Configure Neo4j discovery endpoints using pod DNS
- Set up cluster communication ports (6000, 7000)
- Configure Raft consensus settings
- Test 3-node cluster formation

**Week 6: Load Balancing and Access**
- Configure LoadBalancer Service for cluster access
- Set up health probes for pod health checks
- Test client routing with cluster-aware drivers
- Verify read and write query distribution
- Test failover scenarios (kill leader pod)
- Verify cluster rebalances automatically

**Week 7: Validation and Scenarios**
- Add aks-cluster-v5 scenario (3 nodes)
- Add aks-cluster-5node-v5 scenario (5 nodes)
- Extend validation to check cluster topology
- Verify SHOW SERVERS returns correct node count
- Test cluster survives node pool scaling
- Document cluster deployment process

**Deliverables:**
- Working 3-node and 5-node clusters
- Automatic cluster formation
- Client load balancing working
- Validation tests passing

**Todo list for Phase 3:**
- Research Neo4j cluster discovery configuration for Kubernetes
- Configure StatefulSet replica count based on nodeCount parameter
- Create Headless Service with correct selector and ports
- Generate discovery endpoints list (neo4j-0.neo4j:6000,neo4j-1.neo4j:6000,...)
- Configure Neo4j environment variables for clustering
- Set server.cluster.system_database_mode=PRIMARY for all pods
- Configure server.discovery.v2.endpoints dynamically
- Test cluster formation with 3 pods
- Verify all pods show as Enabled in SHOW SERVERS
- Configure LoadBalancer Service health probes
- Test connection via load balancer IP
- Run write query and verify replication
- Kill leader pod and verify new leader elected
- Verify cluster reforms after pod deletion
- Add aks-cluster-v5 scenario to scenarios.yaml
- Add aks-cluster-5node-v5 scenario
- Update validate_deploy to support cluster topology checks
- Test validation against 3-node cluster
- Test validation against 5-node cluster
- Document cluster architecture and discovery mechanism

### Phase 4: Advanced Features (Weeks 8-10)

**Objective:** Add plugin support, Key Vault integration, and additional scenarios

**Tasks:**

**Week 8: Key Vault Integration**
- Set up Azure Key Vault CSI driver on AKS
- Configure Workload Identity for Key Vault access
- Mount Key Vault secrets into pods
- Test admin password retrieval from Key Vault
- Add keyVaultName parameter support
- Create keyvault-access.bicep module for AKS

**Week 9: Plugin Support**
- Configure GDS plugin installation
- Add init container to download GDS jar
- Configure GDS license key via Secret
- Test GDS procedures
- Configure Bloom plugin installation
- Add Bloom UI access via separate Service
- Test Bloom license and UI access

**Week 10: Additional Scenarios**
- Add aks-cluster-gds scenario
- Add aks-cluster-bloom scenario
- Add aks-cluster-both (GDS + Bloom) scenario
- Create Analytics cluster configuration
- Test all scenarios end-to-end
- Update validation for plugin verification

**Deliverables:**
- Key Vault integration working
- GDS and Bloom plugins installable
- All major scenarios supported
- Validation passing for all scenarios

**Todo list for Phase 4:**
- Install Azure Key Vault CSI driver as AKS add-on
- Configure SecretProviderClass for Neo4j password
- Create keyvault-access.bicep to grant identity Key Vault permissions
- Test password mounted as file in pod
- Configure Neo4j to read password from file
- Verify password retrieval works end-to-end
- Design init container approach for plugin installation
- Create ConfigMap with plugin download URLs
- Add init container to Helm values for GDS
- Mount GDS jar into Neo4j container plugin directory
- Configure GDS license key as Kubernetes Secret
- Test GDS procedures (gds.version, gds.graph.project)
- Create init container for Bloom plugin
- Add Bloom license key as Secret
- Create separate Service for Bloom UI (if needed)
- Test Bloom UI access and license validation
- Add aks-cluster-gds scenario to scenarios.yaml
- Add aks-cluster-bloom scenario
- Add aks-cluster-both scenario
- Configure Analytics cluster topology (1 primary + N secondaries)
- Test Analytics cluster deployment
- Extend validate_deploy to check for GDS and Bloom
- Run full test suite across all scenarios

### Phase 5: Production Readiness (Weeks 11-13)

**Objective:** Harden deployment for production use, add monitoring, docs, and Azure Marketplace packaging

**Tasks:**

**Week 11: Security Hardening**
- Implement Network Policies for pod traffic control
- Configure TLS/SSL for Neo4j connections
- Set up RBAC for least-privilege access
- Configure Pod Security Standards
- Test security configurations
- Document security best practices

**Week 12: Monitoring and Operations**
- Configure Azure Monitor workbook for Neo4j metrics
- Set up log aggregation and queries
- Create alerts for cluster health
- Document backup and restore procedures
- Create runbooks for common operations
- Test disaster recovery scenarios

**Week 13: Documentation and Packaging**
- Write comprehensive user documentation
- Create architecture diagrams
- Update createUiDefinition.json for Azure Portal
- Create makeArchive.sh script
- Test Marketplace submission package
- Create migration guide from VM to AKS deployment
- Final end-to-end testing

**Deliverables:**
- Production-ready deployment
- Complete documentation
- Azure Marketplace package
- Migration guide

**Todo list for Phase 5:**
- Create Network Policy to restrict traffic to Neo4j pods only
- Test Network Policy enforcement
- Configure TLS certificates for Neo4j (self-signed for testing)
- Test encrypted Bolt connections (neo4j+s://)
- Test encrypted HTTPS browser access
- Create Kubernetes RBAC roles for Neo4j service account
- Configure Pod Security Standards (restricted mode)
- Scan container images for vulnerabilities
- Document security configuration options
- Create Azure Monitor workbook template
- Configure container insights for Neo4j pods
- Create log queries for common troubleshooting scenarios
- Set up alerts for pod restarts, OOM kills, etc.
- Document backup approach (volume snapshots + neo4j-admin dump)
- Write restore procedure with step-by-step instructions
- Test backup and restore end-to-end
- Create disaster recovery runbook
- Test cluster recreation from backups
- Write user guide covering all deployment scenarios
- Create architecture diagram showing AKS components
- Create network diagram showing traffic flows
- Document parameter reference for all options
- Update createUiDefinition.json with AKS-specific UI
- Add validation rules for AKS parameters
- Create makeArchive.sh to package Bicep templates
- Test archive.zip structure matches marketplace requirements
- Write migration guide: VM deployment → AKS deployment
- Include data migration steps
- Run full regression test across all scenarios
- Fix any bugs discovered in final testing
- Prepare for marketplace submission

### Phase 6: Testing and Launch (Weeks 14-15)

**Objective:** Final testing, marketplace submission, and launch

**Tasks:**

**Week 14: Comprehensive Testing**
- Run all deployment scenarios in clean subscriptions
- Test with different Azure regions
- Test with various VM sizes for node pools
- Load testing with realistic workloads
- Performance benchmarking vs VM deployments
- Security scanning and penetration testing
- Accessibility testing for UI

**Week 15: Marketplace Submission**
- Submit package to Azure Marketplace
- Address certification feedback
- Final documentation review
- Create launch blog post
- Prepare support documentation
- Train support team
- Coordinate launch communications

**Deliverables:**
- Certified Azure Marketplace offering
- Launch-ready documentation
- Support team trained
- Public announcement

**Todo list for Phase 6:**
- Create fresh Azure subscription for clean testing
- Deploy aks-standalone-v5 in East US, West Europe, Southeast Asia
- Deploy aks-cluster-v5 in multiple regions
- Test with Standard_D4s_v5, Standard_E4s_v5, Standard_D8s_v5 node sizes
- Verify deployments work in subscriptions with quotas
- Run YCSB benchmark against AKS deployment
- Run YCSB benchmark against VM deployment for comparison
- Document performance characteristics
- Run load test with 1000 concurrent connections
- Verify cluster handles failover under load
- Run security scan with Azure Defender
- Review NSG rules and Network Policies
- Test with accessibility tools for Portal UI
- Fix any accessibility issues in createUiDefinition
- Package final archive.zip with makeArchive.sh
- Submit to Azure Partner Portal
- Monitor certification process
- Address any feedback from Azure certification team
- Resubmit if needed
- Review all documentation for accuracy
- Create "Getting Started" guide
- Write blog post announcing AKS offering
- Create comparison table: VM vs AKS deployment
- Prepare FAQ document
- Create support knowledge base articles
- Train support team on AKS-specific troubleshooting
- Prepare launch email and social media posts
- Coordinate launch date with marketing

## Validation Strategy

### Extending the Existing Validation System

The existing validation system in deployments/ can be extended with minimal changes:

**Model extensions:**
- Add `deployment_type` field to TestScenario (values: "vm" or "aks")
- Add AKS-specific fields: `kubernetes_version`, `node_pool_size`, `storage_class`
- Add Helm-related fields: `helm_chart_version`, `helm_values`

**Connection info extraction:**
- For AKS deployments, extract LoadBalancer Service IP instead of VM IP
- Extract Kubernetes cluster name and namespace
- Extract service names and StatefulSet names
- Store kubectl context information

**Validation tests:**
- Existing tests work unchanged (Bolt protocol is the same)
- Add optional Kubernetes resource checks:
  - Verify StatefulSet replicas match expected count
  - Verify all PVCs are bound
  - Verify Service has endpoints
  - Verify pods are Running and Ready

**New scenarios to add:**
- aks-standalone-v5
- aks-cluster-v5
- aks-cluster-5node-v5
- aks-cluster-gds
- aks-cluster-bloom
- aks-analytics-cluster

### GitHub Actions Integration

Create new workflow: `.github/workflows/aks.yml`

**Workflow triggers:**
- Pull requests affecting marketplace/neo4j-enterprise-aks/
- Manual dispatch for testing
- Scheduled weekly run

**Test matrix:**
- Standalone Neo4j 5.x
- 3-node cluster Neo4j 5.x
- Cluster with GDS plugin
- Multiple Azure regions (East US, West Europe)

**Workflow steps:**
1. Create resource group
2. Deploy AKS Bicep template
3. Wait for deployment completion
4. Run validate_deploy for scenario
5. Collect logs if failure
6. Clean up resource group

## Risks and Mitigations

### Risk 1: Helm Chart Complexity
**Risk:** Neo4j Helm charts may have breaking changes or incompatibilities
**Mitigation:**
- Pin to specific Helm chart versions
- Test upgrades in development before production
- Maintain compatibility matrix documentation

### Risk 2: Storage Performance
**Risk:** Azure Disk performance may differ from direct-attached VM disks
**Mitigation:**
- Use Premium SSD storage class
- Benchmark against VM deployments
- Document performance characteristics
- Consider Ultra Disk for high-performance scenarios

### Risk 3: Learning Curve
**Risk:** Users unfamiliar with Kubernetes may struggle
**Mitigation:**
- Provide comprehensive documentation
- Create video tutorials
- Offer managed service option
- Provide migration assistance

### Risk 4: Cost Comparison
**Risk:** AKS may be more expensive than VMs for small deployments
**Mitigation:**
- Clearly document cost structure
- Provide cost calculator
- Highlight benefits beyond cost (reliability, operations)
- Recommend VM deployment for very small workloads

### Risk 5: Networking Complexity
**Risk:** Kubernetes networking may complicate firewall rules
**Mitigation:**
- Provide clear network architecture diagrams
- Document all required ports and protocols
- Offer simple default configuration
- Advanced networking as optional

## Success Criteria

### Technical Metrics
- All deployment scenarios deploy successfully (100% success rate)
- Validation tests pass for all scenarios
- Deployment time < 15 minutes for standalone
- Deployment time < 20 minutes for 3-node cluster
- Cluster formation time < 5 minutes
- Zero data loss during pod rescheduling

### Quality Metrics
- Security scan passes with no high/critical issues
- All documentation reviewed and approved
- User testing feedback positive (>4/5 rating)
- Performance within 10% of VM deployments

### Business Metrics
- Azure Marketplace certification achieved
- Launch within 15 weeks of project start
- Support team trained before launch
- Migration guide published

## Timeline Summary

- **Phase 1 (Weeks 1-2):** Foundation - AKS infrastructure
- **Phase 2 (Weeks 3-4):** Standalone deployment
- **Phase 3 (Weeks 5-7):** Cluster deployment
- **Phase 4 (Weeks 8-10):** Advanced features
- **Phase 5 (Weeks 11-13):** Production readiness
- **Phase 6 (Weeks 14-15):** Testing and launch

**Total: 15 weeks (approximately 4 months)**

## Next Steps

### Immediate Actions (Next 2 Weeks)

1. **Get stakeholder approval** for this proposal
2. **Allocate team resources** - need 1-2 engineers full-time
3. **Set up development environment** - Azure subscription for testing
4. **Research spike** - Spend 2-3 days validating technical assumptions:
   - Deploy Neo4j Helm chart manually to AKS
   - Test cluster formation
   - Verify Bicep can deploy Helm charts
   - Identify any blockers

5. **Refine timeline** based on spike findings
6. **Create project tracking** - GitHub project board or Jira
7. **Schedule kickoff meeting** with engineering team

### Decision Points

**Before starting Phase 1:**
- Confirm Neo4j Helm chart version to target
- Decide on minimum Kubernetes version
- Confirm Azure regions to support
- Approve parameters and UI design

**Before starting Phase 3:**
- Review Phase 2 deliverables
- Decide if standalone deployment meets quality bar
- Approve cluster architecture design

**Before starting Phase 5:**
- Review all functional scenarios
- Decide on security requirements
- Approve monitoring approach

**Before marketplace submission:**
- Final review with product and legal teams
- Approval of pricing model
- Support readiness confirmation

## Conclusion

This AKS-based deployment will modernize the Neo4j Azure offering and meet the needs of Kubernetes-native organizations. By following this phased approach with clear todo lists and success criteria, we can deliver a production-ready solution in approximately 4 months.

The modular Bicep architecture from the existing VM deployment provides a solid foundation, and the validation framework ensures quality throughout development. The key is incremental delivery—starting with standalone, then cluster, then advanced features—allowing for learning and adjustment along the way.

This proposal balances ambition with pragmatism, delivering enterprise-grade features while maintaining simplicity for end users.
