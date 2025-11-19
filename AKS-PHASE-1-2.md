# Neo4j AKS Deployment - Foundation and Standalone Implementation

## Core Principles

### Modern Bicep Architecture (2025)

**Modular Design:**
- Each Azure resource type gets its own Bicep module
- Modules are composable and reusable across deployment types
- Clear separation of concerns between infrastructure and application layers
- No monolithic templates - every module serves a single purpose

**Modern Bicep Features:**
- Use `@description()` decorators on all parameters for self-documenting code
- Use `@minValue()` and `@maxValue()` for validation where applicable
- Use `@allowed()` arrays for enumerated choices
- Use `@secure()` for passwords and sensitive data
- Use `loadTextContent()` for embedding configuration files
- Use user-defined types for complex parameter structures
- Use symbolic names instead of resourceId() functions where possible
- Use existing resource references with existing keyword

**Parameterization Strategy:**
- Required parameters have no defaults (force explicit choices)
- Optional parameters have sensible defaults
- Use parameter objects for grouping related settings
- Document parameter constraints and recommendations in descriptions
- Validate parameters at template level, not in modules

**Output Discipline:**
- Every module outputs only what consuming templates need
- Include resource IDs for dependency tracking
- Include connection strings and endpoints for application access
- Use descriptive output names (not generic like 'id' or 'name')
- Document output purposes in module comments

### Neo4j Best Practices

**Kubernetes Deployment Standards:**
- Use StatefulSets for all Neo4j deployments (never Deployments)
- One StatefulSet per Neo4j role (core servers, analytics secondaries)
- Persistent storage for all data directories
- Stable network identities via headless services
- Init containers for pre-start configuration tasks
- Liveness and readiness probes for health monitoring

**Cluster Formation:**
- Use Kubernetes DNS for service discovery
- Configure discovery endpoints as pod DNS names
- Allow sufficient startup time for cluster consensus
- Use headless service for inter-pod communication
- Use separate load balancer service for client access
- Never rely on pod IPs (always use DNS)

**Storage Management:**
- Azure Disk Premium SSD as default storage class
- One PersistentVolumeClaim per pod (managed by StatefulSet)
- Set volumeClaimTemplates in StatefulSet spec
- Enable volume expansion for future growth
- Use Retain reclaim policy to prevent accidental data loss
- Size disks based on data volume plus 30% growth headroom

**Security Defaults:**
- Admin password must be explicitly provided or retrieved from Key Vault
- Use Workload Identity for all Azure service authentication
- Enable TLS for production deployments
- Network policies to restrict traffic to Neo4j ports only
- Run containers as non-root user
- Read-only root filesystem where possible

**Resource Sizing:**
- Default to 4 CPU cores and 16GB RAM per Neo4j pod
- Allow customization via parameters
- Set both requests and limits (requests = limits for consistent performance)
- Reserve 25% of memory for OS and Kubernetes overhead
- Use node selectors to ensure pods run on appropriate node pool

**Monitoring and Operations:**
- Enable Azure Monitor integration at cluster level
- Stream container logs to Log Analytics workspace
- Expose Neo4j metrics endpoint for Prometheus scraping
- Configure alerts for pod restarts and resource exhaustion
- Tag all resources with deployment metadata

### Development Workflow

**Local Testing Requirements:**
- All templates must deploy successfully via `./deploy.sh`
- All deployments must clean up completely via `./delete.sh`
- Test in isolated resource groups (never modify shared resources)
- Verify in Azure Portal that all resources are created correctly
- Test parameter validation (invalid values should fail gracefully)

**Code Quality Standards:**
- All Bicep files pass `az bicep build` without warnings
- All parameters have descriptions
- All modules have header comments explaining purpose
- No hard-coded values (everything configurable via parameters)
- Consistent naming conventions across all modules

**Documentation Discipline:**
- Update README.md with any new parameters
- Document breaking changes in commit messages
- Include deployment examples in documentation
- Explain why decisions were made, not just what was done
- Keep documentation in sync with code (review both together)

## Implementation Roadmap

This implementation covers two major milestones:

1. **AKS Infrastructure Foundation** - Building the Kubernetes cluster and core infrastructure
2. **Standalone Neo4j Deployment** - Deploying a single-instance Neo4j with full validation

These milestones provide the foundation for all future cluster and advanced scenarios.

---

## Milestone 1: AKS Infrastructure Foundation

**Objective:** Create a production-ready AKS cluster with all supporting infrastructure needed for Neo4j workloads.

**Success Criteria:**
- AKS cluster deploys successfully in multiple Azure regions
- Network security properly configured
- Workload Identity enabled and functional
- Storage class configured for Azure Disk persistence
- All resources tagged for cost tracking
- Clean deletion of all resources

### Infrastructure Architecture

**What we're building:**

An AKS cluster designed specifically for Neo4j workloads, with:
- System node pool for Kubernetes services (DNS, metrics server, monitoring agents)
- User node pool sized for Neo4j pods (scalable based on deployment size)
- Virtual network with appropriate subnet sizing
- Network security group allowing Neo4j traffic patterns
- Managed identity for authenticating to Azure services
- Storage class configured for high-performance disk volumes

**Why this architecture:**
- Separating system and user node pools prevents resource contention
- Dedicated user node pool can be scaled independently
- Network isolation provides security without limiting functionality
- Workload Identity is the modern Azure authentication approach
- Premium SSD storage class ensures acceptable database performance

### Module Breakdown

#### Module 1: Network Infrastructure (network.bicep)

**Purpose:** Create isolated virtual network for AKS with proper segmentation.

**What it provisions:**
- Virtual network with large address space (10.0.0.0/8)
- System subnet for AKS system node pool (10.0.0.0/16)
- User subnet for Neo4j workload node pool (10.1.0.0/16)
- Network Security Group for user subnet with Neo4j port rules
- Service endpoints for Azure storage access

**Security rules to configure:**
- Inbound 7687 (Bolt) - Neo4j client protocol
- Inbound 7474 (HTTP) - Neo4j Browser
- Inbound 7473 (HTTPS) - Secure Neo4j Browser
- Inbound 6000 (TCP) - Neo4j cluster transaction shipping
- Inbound 7000 (TCP) - Neo4j cluster Raft protocol
- Outbound to Azure services (Key Vault, Storage, Monitor)

**Design decisions:**
- Large address space allows for cluster growth
- Separate subnets allow different security policies
- NSG on user subnet only (system subnet managed by AKS)
- Service endpoints reduce latency to Azure services

**Outputs:**
- Virtual network resource ID
- System subnet resource ID
- User subnet resource ID
- Network security group resource ID

#### Module 2: Managed Identity (identity.bicep)

**Purpose:** Create identity for Neo4j pods to authenticate to Azure services.

**What it provisions:**
- User-assigned managed identity
- Federated credential for Workload Identity
- Link between Kubernetes service account and Azure identity

**Why Workload Identity:**
- Modern replacement for deprecated pod identity
- No additional AKS add-ons required
- Better security (short-lived tokens, no secrets)
- Simpler RBAC management

**Configuration details:**
- Federated credential issuer matches AKS OIDC issuer URL
- Subject matches Kubernetes service account namespace and name
- Audience is Azure AD default (api://AzureADTokenExchange)

**Outputs:**
- Managed identity resource ID
- Managed identity client ID (for pod annotation)
- Managed identity principal ID (for RBAC assignments)

#### Module 3: AKS Cluster (aks-cluster.bicep)

**Purpose:** Provision managed Kubernetes cluster with appropriate configuration.

**What it provisions:**
- AKS cluster with automatic Kubernetes version management
- System node pool (Standard_D2s_v5, 3 nodes, autoscaling disabled)
- User node pool (size based on parameter, 1-10 nodes, autoscaling enabled)
- Azure Monitor integration with Log Analytics workspace
- OIDC issuer for Workload Identity
- Azure CNI networking for native VNet integration

**Node pool configuration:**

System pool:
- Small VM size (2 vCPU, 8GB RAM) - sufficient for cluster services
- Fixed 3 nodes for high availability
- System mode (only runs system pods)
- NoSchedule taint to prevent user pods

User pool:
- VM size based on Neo4j requirements (default: Standard_E4s_v5)
- Node count calculated from nodeCount parameter
- User mode (only runs application pods)
- Autoscaling enabled (min 1, max 10)
- Azure Disk storage profile enabled

**Why this design:**
- System pool isolation ensures cluster services always have resources
- User pool can scale based on Neo4j workload demand
- Azure CNI provides pod IPs from VNet (simpler networking)
- Workload Identity is the modern approach (no pod identity add-on)

**Networking specifics:**
- Azure CNI for pod networking (not kubenet)
- Network policy plugin enabled (Azure Network Policy)
- Load balancer SKU: Standard (required for availability zones)
- Private cluster disabled (simplified for marketplace offering)

**Monitoring setup:**
- Container Insights enabled
- Log Analytics workspace in same resource group
- Metrics retention: 30 days
- Diagnostic settings for control plane logs

**Outputs:**
- AKS cluster resource ID
- AKS cluster name
- OIDC issuer URL (for Workload Identity)
- Kubelet identity (for ACR pull)
- Node resource group name

#### Module 4: Storage Configuration (storage.bicep)

**Purpose:** Define storage class for Neo4j persistent volumes.

**What it provisions:**
- StorageClass resource via kubectl command
- Configured for Azure Disk Premium SSD
- Volume expansion enabled
- Retain reclaim policy

**StorageClass specifications:**
- Provisioner: disk.csi.azure.com (Azure Disk CSI driver)
- SKU: Premium_LRS (locally redundant, high IOPS)
- Volume binding mode: WaitForFirstConsumer (creates disk in correct zone)
- Allow volume expansion: true
- Reclaim policy: Retain (volumes persist after pod deletion)

**Why Premium SSD:**
- Consistent performance (not shared, dedicated IOPS)
- Low latency (sub-millisecond)
- Suitable for database workloads
- Predictable cost model

**Why WaitForFirstConsumer:**
- Ensures disk created in same availability zone as pod
- Prevents cross-zone attachment failures
- Critical for zonal AKS clusters

**Deployment approach:**
- Use Bicep deploymentScripts resource
- Run kubectl apply with inline YAML
- Uses AKS user credentials (no separate kubeconfig needed)
- Idempotent (safe to run multiple times)

**Outputs:**
- StorageClass name
- Deployment status

#### Module 5: Main Template (main.bicep)

**Purpose:** Orchestrate all infrastructure modules and define parameters.

**Parameters to define:**

Core deployment settings:
- `location` (required) - Azure region for deployment
- `resourceNamePrefix` (required) - Prefix for all resource names
- `nodeCount` (required) - Number of Neo4j instances (1 for standalone)

AKS configuration:
- `kubernetesVersion` (optional) - Default to stable channel latest
- `systemNodeSize` (optional) - Default to Standard_D2s_v5
- `userNodeSize` (optional) - Default to Standard_E4s_v5
- `userNodeCountMin` (optional) - Default to 1
- `userNodeCountMax` (optional) - Default to 10

Neo4j configuration:
- `graphDatabaseVersion` (required) - "5" or "4.4"
- `diskSize` (required) - Disk size per pod in GB (minimum 32)
- `adminPassword` (secure, required) - Neo4j admin password
- `licenseType` (required) - "Enterprise" or "Evaluation"

**Module orchestration order:**
1. Network (no dependencies)
2. Identity (no dependencies)
3. AKS Cluster (depends on network, identity)
4. Storage (depends on AKS cluster)

**Resource naming convention:**
- Resource group: `{prefix}-aks-{uniqueString}`
- AKS cluster: `{prefix}-aks`
- VNet: `{prefix}-vnet`
- Identity: `{prefix}-identity`
- Log Analytics: `{prefix}-logs`

**Tags to apply:**
- `neo4j-version`: {graphDatabaseVersion}
- `neo4j-edition`: "enterprise"
- `deployment-type`: "aks"
- `node-count`: {nodeCount}
- `created-by`: "neo4j-azure-marketplace"

**Outputs:**
- AKS cluster name
- AKS resource group
- Managed identity client ID
- Log Analytics workspace ID
- OIDC issuer URL
- Connection instructions (as string)

### Directory Structure

```
marketplace/neo4j-enterprise-aks/
├── main.bicep                    # Main orchestration template
├── modules/
│   ├── network.bicep             # VNet and NSG
│   ├── identity.bicep            # Managed identity and Workload Identity
│   ├── aks-cluster.bicep         # AKS cluster with node pools
│   └── storage.bicep             # StorageClass configuration
├── parameters.json               # Default parameters for testing
├── createUiDefinition.json       # Azure Portal UI (placeholder)
├── deploy.sh                     # Local deployment script
├── delete.sh                     # Cleanup script
└── README.md                     # Documentation
```

### Testing and Validation

**Local deployment test:**
1. Run `./deploy.sh test-foundation-eastus`
2. Verify resource group created with all resources
3. Check AKS cluster is running: `az aks show --name X --resource-group Y`
4. Get credentials: `az aks get-credentials --name X --resource-group Y`
5. Verify nodes: `kubectl get nodes` (should see 4 nodes total)
6. Verify storage class: `kubectl get storageclass neo4j-premium`
7. Run `./delete.sh test-foundation-eastus`
8. Verify resource group fully deleted

**Multi-region test:**
1. Deploy to East US, West Europe, Southeast Asia
2. Verify all deployments succeed
3. Check deployment times (should be < 10 minutes)
4. Verify resource naming is consistent
5. Clean up all test resource groups

**Parameter validation test:**
1. Test with nodeCount=1 (should create 1 user node)
2. Test with nodeCount=3 (should create 3 user nodes)
3. Test with invalid parameters (should fail with clear error)
4. Test with minimum disk size (32 GB)
5. Test with large disk size (1024 GB)

---

## Milestone 2: Standalone Neo4j Deployment

**Objective:** Deploy a single-instance Neo4j on AKS with full connectivity and validation.

**Success Criteria:**
- Neo4j pod starts and reaches ready state
- Bolt protocol accessible from outside cluster
- Neo4j Browser accessible via HTTP
- Data persists across pod restarts
- Automated validation passes all tests
- Admin password correctly configured
- License type properly set

### Application Architecture

**What we're building:**

A complete Neo4j deployment consisting of:
- Kubernetes namespace for isolation
- Service account with Workload Identity annotations
- ConfigMap with Neo4j configuration
- Secret containing admin password
- StatefulSet with single replica
- Headless Service for DNS
- LoadBalancer Service for external access
- PersistentVolumeClaim for data storage

**Why StatefulSet:**
- Provides stable network identity (neo4j-0)
- Manages PersistentVolumeClaim lifecycle
- Guarantees ordered, graceful deployment
- Essential for future cluster deployments

**Why two services:**
- Headless service provides stable DNS for pod
- LoadBalancer service provides external access
- Separation allows internal and external routing

### Module Breakdown

#### Module 6: Kubernetes Namespace (namespace.bicep)

**Purpose:** Create isolated namespace for Neo4j resources.

**What it provisions:**
- Kubernetes namespace resource
- Resource labels for identification

**Namespace naming:**
- Default: `neo4j`
- Configurable via parameter for multi-deployment scenarios

**Why namespaces:**
- Logical isolation of Neo4j resources
- Enables RBAC scoping
- Allows multiple Neo4j deployments in same cluster
- Resource quota enforcement (future)

**Deployment approach:**
- Use Bicep deploymentScripts resource
- Run kubectl create namespace
- Idempotent (--dry-run=client -o yaml | kubectl apply)

**Outputs:**
- Namespace name

#### Module 7: Service Account (serviceaccount.bicep)

**Purpose:** Create Kubernetes service account linked to Azure managed identity.

**What it provisions:**
- ServiceAccount resource in Neo4j namespace
- Annotations linking to Workload Identity

**Configuration:**
- Annotation: `azure.workload.identity/client-id` = managed identity client ID
- Annotation: `azure.workload.identity/tenant-id` = Azure tenant ID
- Label: `azure.workload.identity/use: "true"`

**Why this matters:**
- Allows Neo4j pods to authenticate to Key Vault
- No secrets stored in cluster
- Tokens automatically rotated
- Follows Azure best practices

**Outputs:**
- Service account name

#### Module 8: Configuration (configuration.bicep)

**Purpose:** Create ConfigMap and Secret with Neo4j configuration.

**What it provisions:**

ConfigMap with:
- Neo4j server configuration (neo4j.conf settings)
- JVM settings (heap size, GC options)
- Plugin list (APOC by default)
- Deployment metadata

Secret with:
- Admin password (base64 encoded)
- License acceptance flag

**ConfigMap contents:**

Server settings:
- `server.default_listen_address=0.0.0.0` (listen on all interfaces)
- `server.bolt.advertised_address={pod-dns}:7687`
- `server.http.advertised_address={pod-dns}:7474`
- `dbms.security.auth_enabled=true`
- `server.directories.data=/data`
- `server.directories.logs=/logs`

Memory settings:
- `server.memory.heap.initial_size=2G`
- `server.memory.heap.max_size=2G`
- `server.memory.pagecache.size=4G`

**Secret structure:**
- `NEO4J_AUTH`: `neo4j/{adminPassword}` (environment variable format)
- `ACCEPT_LICENSE_AGREEMENT`: `yes` or `eval` based on licenseType

**Why ConfigMap vs environment variables:**
- ConfigMap can be updated without rebuilding images
- Easier to review configuration
- Can be shared across pods in cluster scenarios
- Better for complex multi-line configuration

**Outputs:**
- ConfigMap name
- Secret name

#### Module 9: StatefulSet (statefulset.bicep)

**Purpose:** Deploy Neo4j pod with persistent storage and configuration.

**What it provisions:**
- StatefulSet with single replica
- Volume claim template for data storage
- Init container for data directory setup
- Main Neo4j container
- Liveness and readiness probes

**StatefulSet configuration:**

Replicas: 1 (standalone mode)
Service name: neo4j (links to headless service)
Pod management policy: OrderedReady (strict ordering)

**Volume claim template:**
- Name: data
- Storage class: neo4j-premium
- Access mode: ReadWriteOnce
- Storage size: {diskSize parameter} GB

**Init container:**

Name: init-data-dir
Image: busybox:latest
Purpose: Ensure data directory has correct permissions

Commands:
- Create /data directory if not exists
- Set ownership to neo4j user (UID 7474)
- Set permissions to 755

**Main container:**

Name: neo4j
Image: neo4j:{graphDatabaseVersion}-enterprise
Ports:
- 7474 (HTTP)
- 7687 (Bolt)
- 6000 (cluster transaction)
- 7000 (cluster raft)

Environment variables from:
- ConfigMap (server configuration)
- Secret (auth credentials, license)

Volume mounts:
- data volume → /data
- ConfigMap → /conf/neo4j.conf (subPath)

Resources:
- Requests: 4 CPU, 16Gi memory
- Limits: 4 CPU, 16Gi memory

**Liveness probe:**
- Type: HTTP GET
- Path: /
- Port: 7474
- Initial delay: 300 seconds (5 minutes)
- Period: 10 seconds
- Failure threshold: 3

**Readiness probe:**
- Type: TCP socket
- Port: 7687
- Initial delay: 30 seconds
- Period: 10 seconds
- Failure threshold: 3

**Why these probe settings:**
- Neo4j takes time to start (especially first time)
- Liveness 5-minute delay prevents premature restarts
- Readiness ensures traffic only sent to ready pods
- TCP probe on Bolt is faster than HTTP

**Security context:**
- Run as user: 7474 (neo4j)
- Run as group: 7474
- FSGroup: 7474 (for volume permissions)
- Read-only root filesystem: false (Neo4j needs to write logs)

**Outputs:**
- StatefulSet name
- Pod name (neo4j-0)

#### Module 10: Services (services.bicep)

**Purpose:** Create services for Neo4j access patterns.

**What it provisions:**

Headless Service:
- Name: neo4j
- Type: ClusterIP
- ClusterIP: None (headless)
- Selector: app=neo4j
- Ports: 7474, 7687, 6000, 7000

LoadBalancer Service:
- Name: neo4j-lb
- Type: LoadBalancer
- Selector: app=neo4j
- Ports: 7474 (HTTP), 7687 (Bolt)
- Session affinity: ClientIP (sticky sessions)

**Headless service purpose:**
- Provides DNS: neo4j-0.neo4j.{namespace}.svc.cluster.local
- Used for pod-to-pod communication (future clusters)
- Required for StatefulSet stable identity

**LoadBalancer service purpose:**
- Provisions Azure Load Balancer with public IP
- External clients connect here
- Health probes ensure traffic to healthy pods only

**Service annotations:**
- `service.beta.kubernetes.io/azure-dns-label-name`: {resourcePrefix}-neo4j
- `service.beta.kubernetes.io/azure-load-balancer-health-probe-interval`: 10

**Health probe configuration:**
- Protocol: TCP
- Port: 7687
- Probe interval: 10 seconds
- Number of probes: 2
- Probe threshold: 2

**Why session affinity:**
- Ensures client stays connected to same pod
- Important for transaction consistency
- Less critical for standalone but good practice

**Outputs:**
- Headless service name
- LoadBalancer service name
- External IP address (takes time to provision)

#### Module 11: Application Deployment Orchestrator (neo4j-app.bicep)

**Purpose:** Orchestrate all Kubernetes resource deployment in correct order.

**What it does:**
- Deploys namespace first
- Deploys service account (depends on namespace)
- Deploys configuration (depends on namespace)
- Deploys StatefulSet (depends on configuration, service account)
- Deploys services (depends on StatefulSet labels)

**Parameters:**
- AKS cluster name
- AKS resource group
- Managed identity client ID
- Neo4j version
- Admin password
- License type
- Disk size
- Node count (1 for standalone)

**Deployment method:**
- Use deploymentScripts resources
- Run kubectl apply with inline YAML
- Each resource in separate deployment script
- Sequential dependencies via dependsOn

**Outputs:**
- All Kubernetes resource names
- Connection information
- External IP address
- Browser URL
- Bolt URI

#### Module 12: Main Template Update (main.bicep)

**Purpose:** Extend main template to include Neo4j application deployment.

**What changes:**
- Add new module: neo4j-app.bicep
- Pass AKS cluster info to app module
- Output connection information
- Add dependency chain

**New outputs:**
- `neo4jBrowserUrl`: http://{externalIP}:7474
- `neo4jBoltUri`: neo4j://{externalIP}:7687
- `neo4jUsername`: neo4j
- `neo4jPassword`: {adminPassword} (marked secure)
- `connectionInstructions`: Multi-line string with usage guide

### Connection Information

**What users need:**

Browser access:
1. Get external IP from output
2. Navigate to http://{IP}:7474
3. Login with username: neo4j, password: {adminPassword}

Driver access:
```
URI: neo4j://{IP}:7687
Username: neo4j
Password: {adminPassword}
```

**Kubectl access (for troubleshooting):**
1. Get credentials: `az aks get-credentials --name {cluster} --resource-group {rg}`
2. Check pod: `kubectl get pods -n neo4j`
3. View logs: `kubectl logs neo4j-0 -n neo4j`
4. Port forward: `kubectl port-forward neo4j-0 7474:7474 -n neo4j`

### Testing and Validation

**Deployment test:**
1. Run `./deploy.sh test-standalone-v5`
2. Wait for deployment (approximately 8-12 minutes)
3. Check outputs for connection information
4. Wait 2-3 minutes for external IP provisioning

**Connectivity test:**
1. Copy browser URL from outputs
2. Open in web browser
3. Verify Neo4j Browser loads
4. Login with neo4j/{password}
5. Run query: `RETURN "Hello Neo4j" AS message`
6. Verify query executes successfully

**Persistence test:**
1. Connect to Neo4j Browser
2. Create test data: `CREATE (n:Test {value: 'persistent'})`
3. Delete the pod: `kubectl delete pod neo4j-0 -n neo4j`
4. Wait for pod to restart (30-60 seconds)
5. Reconnect to Neo4j Browser
6. Query: `MATCH (n:Test) RETURN n.value`
7. Verify data still exists

**Validation automation:**
1. Add `aks-standalone-v5` to scenarios.yaml
2. Configure scenario parameters:
   - deployment_type: aks
   - node_count: 1
   - graph_database_version: "5"
   - license_type: "Evaluation"
3. Run: `uv run validate_deploy aks-standalone-v5`
4. Verify all tests pass:
   - Connection successful
   - Movies dataset created
   - Dataset verified
   - License check passed
   - Cleanup successful

### Troubleshooting Guide

**Pod won't start:**
- Check events: `kubectl describe pod neo4j-0 -n neo4j`
- Check logs: `kubectl logs neo4j-0 -n neo4j`
- Common causes: Image pull errors, insufficient resources, PVC binding issues

**Can't connect externally:**
- Verify service: `kubectl get svc neo4j-lb -n neo4j`
- Check external IP is assigned (not pending)
- Verify NSG rules allow traffic on ports 7474 and 7687
- Test from within cluster first: `kubectl run -it --rm debug --image=busybox --restart=Never -- nc -zv neo4j.neo4j.svc.cluster.local 7687`

**PVC won't bind:**
- Check PVC status: `kubectl get pvc -n neo4j`
- Check storage class exists: `kubectl get storageclass neo4j-premium`
- Verify node pool has available capacity
- Check events: `kubectl describe pvc data-neo4j-0 -n neo4j`

**Authentication fails:**
- Verify secret created: `kubectl get secret neo4j-auth -n neo4j`
- Check secret contents: `kubectl get secret neo4j-auth -n neo4j -o yaml`
- Verify Neo4j logs show auth enabled
- Default username is always `neo4j`

---

## Implementation Todo List

### AKS Infrastructure Foundation

**Project Setup:**
- [ ] Create marketplace/neo4j-enterprise-aks directory
- [ ] Create modules subdirectory
- [ ] Create README.md with overview
- [ ] Create .gitignore for local test files
- [ ] Review Neo4j Helm charts documentation
- [ ] Review AKS Bicep documentation and examples
- [ ] Document Azure subscription prerequisites
- [ ] Set up local development environment (Azure CLI, Bicep, kubectl)

**Network Module:**
- [ ] Create modules/network.bicep file
- [ ] Define parameters (location, prefix, vnetAddressSpace, systemSubnetPrefix, userSubnetPrefix)
- [ ] Add parameter descriptions and constraints
- [ ] Create virtual network resource
- [ ] Create system subnet resource
- [ ] Create user subnet resource
- [ ] Create network security group for user subnet
- [ ] Add NSG rules for Neo4j ports (7474, 7687, 6000, 7000)
- [ ] Add NSG rules for HTTPS (7473)
- [ ] Associate NSG with user subnet
- [ ] Define outputs (vnetId, systemSubnetId, userSubnetId, nsgId)
- [ ] Test module in isolation
- [ ] Verify NSG rules in Azure Portal

**Identity Module:**
- [ ] Create modules/identity.bicep file
- [ ] Define parameters (location, identityName)
- [ ] Create user-assigned managed identity resource
- [ ] Define outputs (identityId, clientId, principalId)
- [ ] Test module in isolation
- [ ] Document identity purpose and usage

**AKS Cluster Module:**
- [ ] Create modules/aks-cluster.bicep file
- [ ] Define parameters (all AKS configuration options)
- [ ] Create Log Analytics workspace resource
- [ ] Create AKS cluster resource with symbolic name
- [ ] Configure system node pool (fixed 3 nodes, Standard_D2s_v5)
- [ ] Add NoSchedule taint to system node pool
- [ ] Configure user node pool (scalable, parameter-driven size)
- [ ] Set network profile (Azure CNI, Standard load balancer)
- [ ] Enable OIDC issuer for Workload Identity
- [ ] Enable Workload Identity feature
- [ ] Configure Azure Monitor integration
- [ ] Enable Container Insights
- [ ] Set up diagnostic settings for control plane logs
- [ ] Add identity reference to AKS cluster
- [ ] Define outputs (clusterId, clusterName, oidcIssuerUrl, nodeResourceGroup)
- [ ] Test module in isolation
- [ ] Verify node pools in Azure Portal
- [ ] Get credentials and verify cluster access

**Storage Module:**
- [ ] Create modules/storage.bicep file
- [ ] Define parameters (aksClusterName, aksResourceGroup, storageClassName)
- [ ] Create deploymentScripts resource for kubectl
- [ ] Write StorageClass YAML as inline string
- [ ] Configure Azure Disk CSI provisioner
- [ ] Set Premium_LRS as disk type
- [ ] Enable volume expansion
- [ ] Set Retain reclaim policy
- [ ] Set WaitForFirstConsumer binding mode
- [ ] Test storage class creation
- [ ] Verify storage class appears in kubectl
- [ ] Define outputs (storageClassName)

**Main Template:**
- [ ] Create main.bicep file
- [ ] Define all deployment parameters with descriptions
- [ ] Add parameter validation rules
- [ ] Create network module reference
- [ ] Create identity module reference
- [ ] Create AKS cluster module reference (depends on network, identity)
- [ ] Create storage module reference (depends on AKS)
- [ ] Define resource naming variables
- [ ] Add resource tags for all resources
- [ ] Define comprehensive outputs
- [ ] Add connection instructions output
- [ ] Test full template deployment
- [ ] Verify all resources created correctly

**Testing Infrastructure:**
- [ ] Create parameters.json with test values
- [ ] Create deploy.sh script
- [ ] Add validation in deploy.sh (check Azure CLI installed)
- [ ] Add resource group creation in deploy.sh
- [ ] Add Bicep build command
- [ ] Add deployment command with parameters
- [ ] Add output display
- [ ] Create delete.sh script
- [ ] Add confirmation prompt in delete.sh
- [ ] Test deployment in East US
- [ ] Test deployment in West Europe
- [ ] Test deployment in Southeast Asia
- [ ] Verify clean deletion in all regions
- [ ] Document deployment time for each region

**Documentation:**
- [ ] Write README.md overview section
- [ ] Document architecture decisions
- [ ] Document all parameters with examples
- [ ] Add deployment instructions
- [ ] Add troubleshooting section
- [ ] Document Azure permissions required
- [ ] Add diagrams for network architecture
- [ ] Add cost estimation guidance

### Standalone Neo4j Deployment

**Kubernetes Resources - Namespace:**
- [ ] Create modules/namespace.bicep file
- [ ] Define parameters (namespaceName, labels)
- [ ] Create deploymentScripts resource for kubectl
- [ ] Write namespace YAML inline
- [ ] Make deployment idempotent
- [ ] Test namespace creation
- [ ] Verify namespace in kubectl
- [ ] Define outputs

**Kubernetes Resources - Service Account:**
- [ ] Create modules/serviceaccount.bicep file
- [ ] Define parameters (namespace, serviceAccountName, identityClientId)
- [ ] Create deploymentScripts resource
- [ ] Write ServiceAccount YAML with Workload Identity annotations
- [ ] Add azure.workload.identity/client-id annotation
- [ ] Add azure.workload.identity/use label
- [ ] Test service account creation
- [ ] Verify annotations in kubectl
- [ ] Define outputs

**Kubernetes Resources - Configuration:**
- [ ] Create modules/configuration.bicep file
- [ ] Define parameters (namespace, adminPassword, licenseType, graphDatabaseVersion)
- [ ] Research Neo4j container environment variables
- [ ] Design ConfigMap structure for neo4j.conf
- [ ] Write ConfigMap YAML with server settings
- [ ] Add memory configuration (heap, pagecache)
- [ ] Add advertised addresses (template)
- [ ] Write Secret YAML for admin password
- [ ] Encode password in base64
- [ ] Add license acceptance to secret
- [ ] Create deployment scripts for both resources
- [ ] Test ConfigMap creation
- [ ] Test Secret creation
- [ ] Verify secret is not readable in output
- [ ] Define outputs

**Kubernetes Resources - StatefulSet:**
- [ ] Create modules/statefulset.bicep file
- [ ] Define all StatefulSet parameters
- [ ] Research Neo4j container best practices
- [ ] Write StatefulSet YAML structure
- [ ] Configure metadata with labels and annotations
- [ ] Set replicas to 1 (standalone)
- [ ] Configure service name reference
- [ ] Write pod template spec
- [ ] Add service account reference
- [ ] Configure security context (user 7474, fsGroup 7474)
- [ ] Write init container YAML for permissions
- [ ] Configure main Neo4j container
- [ ] Set container image with version parameter
- [ ] Add all ports (7474, 7687, 6000, 7000)
- [ ] Configure environment variables from ConfigMap
- [ ] Configure environment variables from Secret
- [ ] Add volume mounts for data and config
- [ ] Configure resource requests (4 CPU, 16Gi)
- [ ] Configure resource limits (same as requests)
- [ ] Write liveness probe (HTTP, 5 min delay)
- [ ] Write readiness probe (TCP, 30 sec delay)
- [ ] Write volume claim template
- [ ] Set storage class name
- [ ] Set storage size from parameter
- [ ] Set access mode to ReadWriteOnce
- [ ] Test StatefulSet deployment
- [ ] Verify pod starts successfully
- [ ] Check logs for Neo4j startup
- [ ] Verify PVC created and bound
- [ ] Define outputs

**Kubernetes Resources - Services:**
- [ ] Create modules/services.bicep file
- [ ] Define parameters (namespace, serviceName, selector labels)
- [ ] Write headless Service YAML
- [ ] Set ClusterIP to None
- [ ] Configure all ports (7474, 7687, 6000, 7000)
- [ ] Set selector to match StatefulSet pods
- [ ] Write LoadBalancer Service YAML
- [ ] Configure external-facing ports (7474, 7687)
- [ ] Add Azure DNS label annotation
- [ ] Add health probe annotations
- [ ] Configure session affinity (ClientIP)
- [ ] Create deployment scripts for both services
- [ ] Test service creation
- [ ] Wait for LoadBalancer external IP
- [ ] Retrieve external IP from kubectl
- [ ] Verify IP is accessible
- [ ] Define outputs (service names and external IP)

**Application Orchestrator:**
- [ ] Create modules/neo4j-app.bicep file
- [ ] Define all application parameters
- [ ] Add namespace module reference
- [ ] Add service account module reference (depends on namespace)
- [ ] Add configuration module reference (depends on namespace)
- [ ] Add StatefulSet module reference (depends on config and SA)
- [ ] Add services module reference (depends on StatefulSet)
- [ ] Create proper dependency chain
- [ ] Add wait logic for external IP assignment
- [ ] Define comprehensive outputs
- [ ] Generate browser URL output
- [ ] Generate Bolt URI output
- [ ] Test full application deployment
- [ ] Verify all resources created in order

**Main Template Updates:**
- [ ] Update main.bicep to include neo4j-app module
- [ ] Add neo4j-app as dependent on storage module
- [ ] Pass AKS cluster info to application module
- [ ] Pass identity client ID to application module
- [ ] Update outputs with connection information
- [ ] Add connection instructions to outputs
- [ ] Test full end-to-end deployment
- [ ] Time the full deployment process
- [ ] Document deployment steps

**Connectivity Testing:**
- [ ] Deploy standalone instance fully
- [ ] Wait for all resources to be ready
- [ ] Copy connection information from outputs
- [ ] Test Neo4j Browser access via HTTP
- [ ] Verify browser loads without errors
- [ ] Test login with admin credentials
- [ ] Run simple Cypher query (RETURN 1)
- [ ] Run CREATE query to add data
- [ ] Verify data persists
- [ ] Test Bolt connection with Python driver
- [ ] Test Bolt connection with Java driver
- [ ] Document connection process

**Persistence Testing:**
- [ ] Connect to Neo4j instance
- [ ] Create substantial test dataset
- [ ] Record dataset size and query results
- [ ] Delete Neo4j pod forcefully
- [ ] Wait for pod to restart
- [ ] Reconnect to Neo4j
- [ ] Verify all data still exists
- [ ] Run same queries, verify same results
- [ ] Check PVC remains bound during restart
- [ ] Document persistence behavior

**Validation Integration:**
- [ ] Navigate to deployments directory
- [ ] Open config/scenarios.yaml
- [ ] Add aks-standalone-v5 scenario definition
- [ ] Set deployment_type to "aks"
- [ ] Configure all scenario parameters
- [ ] Review validate_deploy.py code
- [ ] Understand connection info extraction
- [ ] Update DeploymentEngine if needed for AKS
- [ ] Update connection info extraction for Kubernetes Service IPs
- [ ] Test deployment via deployment system
- [ ] Run validate_deploy for new scenario
- [ ] Verify connection test passes
- [ ] Verify cluster topology check (1 node expected)
- [ ] Verify Movies dataset test passes
- [ ] Verify license check passes
- [ ] Verify cleanup passes
- [ ] Fix any validation failures
- [ ] Document validation process

**Documentation:**
- [ ] Update README.md with standalone deployment section
- [ ] Document all Kubernetes resources created
- [ ] Add architecture diagram for standalone deployment
- [ ] Document connection methods (Browser, Bolt, kubectl)
- [ ] Write troubleshooting guide for common issues
- [ ] Document how to view logs
- [ ] Document how to access pod shell
- [ ] Add FAQ section
- [ ] Document data persistence behavior
- [ ] Add performance expectations
- [ ] Document resource requirements
- [ ] Add cost estimation for standalone deployment
- [ ] Review all documentation for accuracy

**GitHub Actions Integration:**
- [ ] Create .github/workflows/aks.yml file
- [ ] Configure workflow triggers (PR, manual, schedule)
- [ ] Add job for standalone deployment test
- [ ] Configure Azure credentials via secrets
- [ ] Add step to deploy Bicep template
- [ ] Add step to wait for deployment
- [ ] Add step to run validation
- [ ] Add step to collect logs on failure
- [ ] Add step to cleanup resources
- [ ] Test workflow with manual trigger
- [ ] Verify workflow succeeds end-to-end
- [ ] Fix any workflow issues
- [ ] Document workflow usage

---

## Success Metrics

**Infrastructure Foundation:**
- AKS cluster deploys in under 10 minutes
- All resources tagged correctly
- Network security configured properly
- Storage class functional
- Clean deletion leaves no orphaned resources

**Standalone Deployment:**
- Complete deployment (infrastructure + application) in under 15 minutes
- Neo4j reachable within 2 minutes of pod being ready
- Data survives pod restart with zero data loss
- Validation passes 100% of tests
- Documentation complete and accurate

**Development Workflow:**
- Deploy script works on first try
- Delete script removes all resources
- No manual Azure Portal steps required
- All parameters have clear descriptions
- Error messages are actionable

## Next Steps After Completion

Once both milestones are complete:

1. **Code review:** Have team review all Bicep modules and Kubernetes YAML
2. **Security review:** Scan for security issues and hardening opportunities
3. **Performance baseline:** Document deployment times and resource usage
4. **Cost analysis:** Calculate cost per hour for standalone deployment
5. **User testing:** Have non-author deploy and provide feedback
6. **Documentation review:** Ensure documentation is clear and complete

After validation, proceed to cluster deployment (next phase), which will build on this foundation by:
- Increasing StatefulSet replicas
- Adding cluster discovery configuration
- Testing cluster formation
- Validating failover scenarios
