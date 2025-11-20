# Bicep to Helm Parameter Mapping

## Overview

This document maps Azure Bicep template parameters to Neo4j Helm chart values for the AKS deployment.

**Helm Chart**: `neo4j/neo4j` (official Neo4j Helm chart)
**Chart Repository**: https://helm.neo4j.com/neo4j
**Documentation**: https://github.com/neo4j/helm-charts

---

## Parameter Mapping Table

| Bicep Parameter | Type | Helm Values Path | Helm Value Type | Notes |
|-----------------|------|------------------|-----------------|-------|
| `nodeCount` | int | `neo4j.minimumClusterSize` | int | 1 for standalone, 3+ for cluster |
| `graphDatabaseVersion` | string | `image.tag` | string | e.g., "5", "5.15.0" |
| `diskSize` | int | `volumes.data.dynamic.storage` | string | Add "Gi" suffix |
| `adminPassword` | securestring | `neo4j.password` | string | Passed as Helm value |
| `licenseType` | string | `neo4j.acceptLicenseAgreement` | string | "Evaluation" → "eval", "Enterprise" → "yes" |
| `installGraphDataScience` | bool | `config` | object | Custom NEO4J_PLUGINS configuration |
| `installBloom` | bool | `config` | object | Custom NEO4J_PLUGINS configuration |
| `cpuRequest` | string | `resources.cpu` | string | Helm uses single value for request/limit |
| `memoryRequest` | string | `resources.memory` | string | Helm uses single value for request/limit |
| `userNodeSize` | string | N/A | - | Affects AKS infrastructure, not Helm |
| `kubernetesVersion` | string | N/A | - | Affects AKS infrastructure, not Helm |

---

## Detailed Mapping

### 1. Node Count / Cluster Size

**Bicep Parameter:**
```bicep
param nodeCount int = 1
```

**Helm Values:**
```yaml
neo4j:
  minimumClusterSize: 1  # standalone
  # OR
  minimumClusterSize: 3  # 3-node cluster
```

**Mapping Logic:**
- `nodeCount = 1` → Standalone mode (`minimumClusterSize: 1`)
- `nodeCount >= 3` → Cluster mode (`minimumClusterSize: <nodeCount>`)

**Notes:**
- Helm chart handles StatefulSet replica count automatically based on cluster size
- Minimum cluster size of 3 recommended for production

---

### 2. Neo4j Version

**Bicep Parameter:**
```bicep
param graphDatabaseVersion string = '5'
```

**Helm Values:**
```yaml
image:
  tag: "5"  # or specific version like "5.15.0"
  customImage: null  # use default neo4j image
```

**Mapping Logic:**
- Use the value directly as image tag
- Helm chart defaults to `neo4j:5-enterprise` for enterprise edition

**Notes:**
- Only Neo4j 5.x supported (no 4.4)
- Can specify minor versions (e.g., "5.15.0") for specific releases

---

### 3. Storage Configuration

**Bicep Parameter:**
```bicep
param diskSize int = 32
```

**Helm Values:**
```yaml
volumes:
  data:
    mode: "dynamic"  # Use dynamic provisioning
    dynamic:
      storageClassName: "managed-premium"  # Azure Premium SSD
      storage: "32Gi"  # Add Gi suffix
      accessModes:
        - ReadWriteOnce
```

**Mapping Logic:**
```
diskSize (GB) → "${diskSize}Gi"
```

**Notes:**
- Always use `mode: "dynamic"` for Azure
- Storage class: `managed-premium` for Premium SSD
- Access mode: `ReadWriteOnce` (one pod per volume)

---

### 4. Admin Password

**Bicep Parameter:**
```bicep
@secure()
param adminPassword string
```

**Helm Values:**
```yaml
neo4j:
  password: "<secure-password>"  # Passed at deployment time
```

**Mapping Logic:**
- Pass directly to Helm as `--set neo4j.password=<password>`
- Alternatively, use `--set-file` for added security

**Notes:**
- Password auto-generated if not specified (not suitable for our use case)
- Consider using Azure Key Vault integration in future

---

### 5. License Configuration

**Bicep Parameter:**
```bicep
param licenseType string = 'Evaluation'
```

**Helm Values:**
```yaml
neo4j:
  edition: "enterprise"  # Always enterprise for our offering
  acceptLicenseAgreement: "eval"  # or "yes" for production
```

**Mapping Logic:**
```
licenseType = "Evaluation" → acceptLicenseAgreement: "eval"
licenseType = "Enterprise" → acceptLicenseAgreement: "yes"
```

**Notes:**
- Edition always "enterprise" (no community in this offering)
- "eval" for evaluation licenses, "yes" for production licenses

---

### 6. Resource Configuration

**Bicep Parameters:**
```bicep
param cpuRequest string = '2'
param cpuLimit string = '3'
param memoryRequest string = '8Gi'
param memoryLimit string = '12Gi'
```

**Helm Values:**
```yaml
resources:
  cpu: "2000m"  # Helm uses single value (request = limit)
  memory: "8Gi"
```

**Mapping Logic:**
- Use request values (Helm sets request = limit)
- Convert CPU to millicores: `"2"` → `"2000m"`
- Memory keeps Gi suffix

**Notes:**
- Helm chart doesn't differentiate requests/limits
- Conservative approach: use request values
- Future enhancement: Make configurable

---

### 7. Graph Data Science Plugin

**Bicep Parameter:**
```bicep
param installGraphDataScience bool = false
```

**Helm Values:**
```yaml
config:
  NEO4J_PLUGINS: '["graph-data-science"]'  # if true
```

**Mapping Logic:**
```
installGraphDataScience = true → NEO4J_PLUGINS includes "graph-data-science"
installGraphDataScience = false → NEO4J_PLUGINS excludes GDS
```

**Notes:**
- GDS license key handled separately
- Requires Neo4j Enterprise edition

---

### 8. Bloom Plugin

**Bicep Parameter:**
```bicep
param installBloom bool = false
```

**Helm Values:**
```yaml
config:
  NEO4J_PLUGINS: '["bloom"]'  # if true
```

**Mapping Logic:**
```
installBloom = true → NEO4J_PLUGINS includes "bloom"
installBloom = false → NEO4J_PLUGINS excludes Bloom
```

**Combined Plugins Example:**
```yaml
config:
  NEO4J_PLUGINS: '["graph-data-science", "bloom"]'  # both enabled
```

**Notes:**
- Bloom license key handled separately
- Requires Neo4j Enterprise edition

---

## Helm-Specific Values (No Bicep Equivalent)

### Service Configuration

```yaml
services:
  neo4j:
    enabled: true
    type: LoadBalancer  # For Azure external access
  default:
    enabled: true
    type: ClusterIP  # For internal cluster communication
```

**Notes:**
- LoadBalancer type creates Azure Load Balancer
- Exposes ports 7474 (HTTP), 7687 (Bolt)

---

### Pod Security Context

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 7474
  runAsGroup: 7474
  fsGroup: 7474
podSecurityContext:
  fsGroupChangePolicy: "OnRootMismatch"
```

**Notes:**
- Helm chart provides secure defaults
- No Bicep parameter needed

---

### Probes

```yaml
readinessProbe:
  tcpSocket:
    port: 7687
  failureThreshold: 20
  periodSeconds: 5

livenessProbe:
  tcpSocket:
    port: 7687
  failureThreshold: 40
  periodSeconds: 5

startupProbe:
  tcpSocket:
    port: 7687
  failureThreshold: 1000
  periodSeconds: 5
```

**Notes:**
- Helm chart provides robust probe configuration
- Startup probe allows for slow cluster formation

---

## Example Helm Values File

### Standalone Deployment

```yaml
neo4j:
  name: "neo4j-standalone"
  edition: "enterprise"
  acceptLicenseAgreement: "eval"
  password: "<secure-password>"
  minimumClusterSize: 1

image:
  tag: "5"

volumes:
  data:
    mode: "dynamic"
    dynamic:
      storageClassName: "managed-premium"
      storage: "32Gi"

resources:
  cpu: "2000m"
  memory: "8Gi"

config:
  server.memory.heap.initial_size: "4G"
  server.memory.heap.max_size: "4G"
  server.memory.pagecache.size: "3G"
```

### 3-Node Cluster Deployment

```yaml
neo4j:
  name: "neo4j-cluster"
  edition: "enterprise"
  acceptLicenseAgreement: "yes"
  password: "<secure-password>"
  minimumClusterSize: 3

image:
  tag: "5"

volumes:
  data:
    mode: "dynamic"
    dynamic:
      storageClassName: "managed-premium"
      storage: "32Gi"

resources:
  cpu: "2000m"
  memory: "8Gi"

config:
  server.memory.heap.initial_size: "4G"
  server.memory.heap.max_size: "4G"
  server.memory.pagecache.size: "3G"
  dbms.cluster.discovery.resolver_type: "LIST"
  dbms.cluster.minimum_initial_system_primaries_count: "3"
```

---

## Helm Chart Installation Command

### Standalone
```bash
helm install neo4j neo4j/neo4j \
  --namespace neo4j \
  --create-namespace \
  --set neo4j.password=<password> \
  --set neo4j.edition=enterprise \
  --set neo4j.acceptLicenseAgreement=eval \
  --set volumes.data.mode=dynamic \
  --set volumes.data.dynamic.storageClassName=managed-premium \
  --set volumes.data.dynamic.storage=32Gi \
  --set resources.cpu=2000m \
  --set resources.memory=8Gi
```

### Cluster (via values file)
```bash
helm install neo4j neo4j/neo4j \
  --namespace neo4j \
  --create-namespace \
  --values cluster-values.yaml
```

---

## Notes for Bicep Implementation

1. **Helm Repository Configuration**
   - Add Neo4j Helm repo: `helm repo add neo4j https://helm.neo4j.com/neo4j`
   - Update repos: `helm repo update`

2. **Deployment Script Approach**
   - Use Bicep `deploymentScripts` resource
   - Run `helm install` with dynamically generated values
   - Pass parameters via `--set` flags or generate values.yaml file

3. **Values File Generation**
   - Option A: Generate values.yaml in deploymentScript
   - Option B: Use multiple `--set` flags (simpler for initial implementation)

4. **Upgrade Strategy**
   - Use `helm upgrade --install` for idempotency
   - Track Helm release name in Bicep outputs

5. **Cleanup**
   - Helm uninstall via `helm uninstall neo4j --namespace neo4j`
   - Resource group deletion handles everything in Azure

---

## Version Compatibility

| Bicep Template Version | Neo4j Helm Chart Version | Neo4j Version | AKS Version |
|------------------------|-------------------------|---------------|-------------|
| Phase 1 (initial) | Latest (5.x compatible) | 5.x Enterprise | 1.30+ |

---

## Future Enhancements

- [ ] Support for custom Neo4j configuration via config map
- [ ] Integration with Azure Key Vault for secrets
- [ ] Support for Azure Backup integration
- [ ] Monitoring integration with Azure Monitor
- [ ] Multi-region deployment support
- [ ] Automated backups via Helm chart backup feature

---

**Last Updated**: November 19, 2025
**Author**: Development Team
**Status**: Phase 1 Implementation
