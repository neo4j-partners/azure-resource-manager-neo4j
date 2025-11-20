# Neo4j AKS Marketplace Offering - Helm Chart Migration Proposal

## Best Practices Foundation

This proposal follows Neo4j Kubernetes best practices documented at:
- **Neo4j Operations Manual**: https://neo4j.com/docs/operations-manual/5/kubernetes/
- **Neo4j Helm Charts**: https://github.com/neo4j/helm-charts

**Target Version**: Neo4j 5.x Enterprise only
**Deprecated Features**: Neo4j 4.4 and Read Replicas are not supported in this architecture

---

## Executive Summary

This proposal outlines the migration from a custom Bicep-based kubectl deployment approach to a Helm chart-based architecture that complies with Microsoft Azure Marketplace requirements for Kubernetes applications. The migration will leverage the official Neo4j Helm charts to ensure best practices, reduce maintenance burden, and enable Azure Marketplace certification.

**Key Drivers:**
- Azure Marketplace **requires** Helm chart-based applications for Kubernetes offerings (as of January 2024)
- Official Neo4j Helm charts provide battle-tested Neo4j 5.x clustering configuration
- Reduced maintenance burden by leveraging Neo4j's official charts
- Automatic compatibility with future Neo4j releases

**Timeline**: 6-8 weeks for complete migration and Azure Marketplace certification

---

## Current State Assessment

### What Works ✅
- **AKS Infrastructure Deployment**: Bicep templates successfully create AKS clusters, networking, identities, and monitoring
- **Standalone Neo4j 5.x**: Single-node deployments work correctly
- **VM-Based Offerings**: Existing VMSS-based marketplace offerings remain valid and unaffected

### What Needs Fixing ❌
- **Cluster Deployment**: Using Neo4j 4.4 configuration syntax for 5.x clustering (causing crashes)
- **Marketplace Compliance**: Custom kubectl approach not suitable for Azure Marketplace Kubernetes offers
- **Configuration Maintenance**: Manual maintenance of Neo4j configuration increases risk of drift from best practices

---

## Architecture Changes

### Current Architecture (Phase 2)
```
Azure Portal/CLI
    ↓
main.bicep (orchestrator)
    ↓
├── Infrastructure Modules (AKS, Network, Identity) ✅ Keep
└── Application Modules (kubectl-based YAML deployment) ❌ Replace
        ↓
    Custom Neo4j StatefulSet, ConfigMap, Services
```

### Target Architecture (Helm-Based)
```
Azure Portal/CLI
    ↓
main.bicep (orchestrator)
    ↓
├── Infrastructure Modules (AKS, Network, Identity) ✅ Keep as-is
└── Helm Deployment Module (new) ✅ Add
        ↓
    Neo4j Official Helm Chart
        ↓
    StatefulSet, ConfigMap, Services (managed by Helm)
```

### Azure Marketplace Packaging
```
CNAB Bundle (Cloud Native Application Bundle)
    ├── Neo4j Helm Chart (application)
    ├── AKS Infrastructure (Bicep)
    └── Marketplace Metadata (UI definitions, pricing)
```

---

## Migration Phases

### Phase 1: Helm Chart Integration (Weeks 1-2)

**Objective**: Replace custom kubectl deployments with Neo4j Helm chart while maintaining Bicep infrastructure.

**Activities**:
1. **Research and Planning**
   - Study official Neo4j Helm chart structure and configuration options
   - Identify equivalent settings for current parameters (nodeCount, disk size, version, etc.)
   - Document mapping between current Bicep parameters and Helm values

2. **Create Helm Deployment Module**
   - Design new Bicep module that uses deploymentScripts to run `helm install`
   - Pass AKS cluster credentials and context to Helm installation
   - Map user-provided parameters to Helm values.yaml structure
   - Handle Helm chart repository configuration and versioning

3. **Parameter Mapping**
   - Map `nodeCount` to Helm replica count
   - Map `diskSize` to PersistentVolume size
   - Map `licenseType` to Neo4j license acceptance
   - Map `adminPassword` to Helm secrets management
   - Map AKS node sizing to Neo4j resource requests/limits

4. **Remove Custom Kubernetes Modules**
   - Archive current modules: namespace.bicep, serviceaccount.bicep, configuration.bicep, statefulset.bicep, services.bicep
   - Document what each module did for reference
   - Keep neo4j-app.bicep structure but replace implementation

**Deliverables**:
- New `helm-deployment.bicep` module
- Updated `neo4j-app.bicep` orchestrator using Helm
- Parameter mapping documentation
- Working standalone deployment using Helm chart

**Testing**:
- Deploy standalone Neo4j 5.x via Helm chart
- Verify database functionality and connectivity
- Confirm resource creation matches previous approach
- Validate parameter passthrough

---

### Phase 2: Cluster Configuration (Weeks 3-4)

**Objective**: Enable multi-node Neo4j clustering using Helm chart's built-in cluster support.

**Activities**:
1. **Helm Cluster Configuration Research**
   - Study Neo4j Helm chart clustering configuration
   - Understand how Helm handles cluster formation and discovery
   - Document cluster-specific Helm values

2. **Configure Cluster Deployment**
   - Set Helm values for replica count based on `nodeCount` parameter
   - Configure cluster discovery endpoints (handled automatically by Helm)
   - Set initial cluster size and quorum requirements
   - Configure persistent volume claims per replica

3. **RBAC and Permissions**
   - Ensure service account has necessary permissions for cluster discovery
   - Configure workload identity integration
   - Set up role bindings for Kubernetes API access if needed

4. **Network Configuration**
   - Configure headless service for cluster communication (managed by Helm)
   - Configure LoadBalancer service for external access
   - Set up proper port mappings for Bolt, HTTP, and cluster ports

5. **Storage Configuration**
   - Configure StorageClass for Premium SSD
   - Set up persistent volume claim templates
   - Configure volume mount paths

**Deliverables**:
- Helm values configuration for 3-node clusters
- Helm values configuration for 5-node clusters
- Updated test scenarios for cluster deployments
- Cluster formation validation scripts

**Testing**:
- Deploy 3-node Neo4j cluster
- Verify cluster formation and all members present (SHOW SERVERS)
- Test failover and leader election
- Verify data replication across nodes
- Deploy 5-node cluster and validate

---

### Phase 3: Advanced Features (Weeks 5-6)

**Objective**: Add plugin support, monitoring integration, and backup capabilities.

**Activities**:
1. **Graph Data Science Plugin**
   - Configure Helm values for GDS plugin installation
   - Handle GDS license key securely
   - Test GDS algorithms on cluster

2. **Bloom Plugin**
   - Configure Helm values for Bloom plugin installation
   - Handle Bloom license key securely
   - Verify Bloom visualization capabilities

3. **Monitoring Integration**
   - Configure Prometheus metrics export via Helm
   - Integrate with Azure Monitor Container Insights
   - Set up alerting for cluster health

4. **Backup Strategy**
   - Configure backup schedules via Helm if supported
   - Implement volume snapshot configuration
   - Document backup and restore procedures

**Deliverables**:
- GDS plugin integration via Helm
- Bloom plugin integration via Helm
- Monitoring dashboard configuration
- Backup/restore documentation

**Testing**:
- Verify GDS plugin functionality
- Verify Bloom access and visualization
- Test monitoring metrics collection
- Validate backup and restore procedures

---

### Phase 4: Azure Marketplace Certification (Weeks 7-8)

**Objective**: Package the solution as a CNAB bundle and certify for Azure Marketplace.

**Activities**:
1. **CNAB Bundle Creation**
   - Package Helm chart as Cloud Native Application Bundle
   - Include AKS infrastructure Bicep templates
   - Configure bundle manifest and metadata
   - Publish bundle to Azure Container Registry

2. **Marketplace Offer Configuration**
   - Update Azure Partner Center offer definition
   - Configure pricing models (BYOL, consumption-based)
   - Set up lead management integration
   - Configure offer preview for testing

3. **UI Definition Updates**
   - Update createUiDefinition.json for Helm-based deployment
   - Simplify parameters where Helm provides sensible defaults
   - Add validation for cluster sizing recommendations
   - Update deployment instructions and documentation

4. **Security and Compliance**
   - Scan Helm chart and container images for vulnerabilities
   - Address any security findings
   - Ensure compliance with Azure Marketplace policies
   - Document security configurations

5. **Certification Testing**
   - Deploy via Azure Marketplace preview
   - Test all deployment scenarios (standalone, 3-node, 5-node)
   - Verify billing integration
   - Conduct end-to-end user acceptance testing

**Deliverables**:
- CNAB bundle published to ACR
- Updated Azure Marketplace offer
- Updated createUiDefinition.json
- Security scan reports
- Certification test results
- Updated documentation

**Testing**:
- Marketplace preview deployments
- Multi-region deployment testing
- Upgrade scenario testing
- Performance and scale testing

---

## Testing Strategy

### Unit Testing
- Each Helm values configuration tested in isolation
- Parameter validation and error handling
- Resource creation verification

### Integration Testing
- Full deployment via Bicep → Helm chain
- Multi-scenario testing (standalone, cluster)
- Plugin installation verification

### End-to-End Testing
- Deployment through Azure Portal
- Deployment through Azure CLI
- Deployment through ARM REST API
- Deployment through Azure Marketplace

### Performance Testing
- Large dataset ingestion
- Concurrent query performance
- Cluster rebalancing
- Failover recovery time

### Security Testing
- Vulnerability scanning
- Penetration testing
- Compliance validation
- RBAC configuration review

---

## Risk Mitigation

### Risk: Helm Chart Configuration Complexity
- **Mitigation**: Start with minimal configuration, add features incrementally
- **Mitigation**: Extensive testing at each phase
- **Mitigation**: Consult Neo4j documentation and community

### Risk: Azure Marketplace Certification Delays
- **Mitigation**: Engage Microsoft Partner support early
- **Mitigation**: Follow all Marketplace guidelines from start
- **Mitigation**: Allow buffer time for certification review

### Risk: Breaking Changes from Neo4j Helm Chart Updates
- **Mitigation**: Pin specific Helm chart versions
- **Mitigation**: Test new chart versions in staging before production
- **Mitigation**: Document chart version compatibility matrix

### Risk: Migration Disrupts Existing Deployments
- **Mitigation**: Keep VM-based offerings unchanged
- **Mitigation**: Version AKS offering separately
- **Mitigation**: Extensive testing before production release

---

## Success Criteria

### Phase 1 Success
- [ ] Standalone Neo4j 5.x deploys successfully via Helm
- [ ] All parameters map correctly from Bicep to Helm
- [ ] Database is accessible and functional
- [ ] Deployment time under 20 minutes

### Phase 2 Success
- [ ] 3-node cluster forms successfully
- [ ] All cluster members visible via SHOW SERVERS
- [ ] Data replicates across all nodes
- [ ] Automatic failover works correctly
- [ ] 5-node cluster deploys and operates correctly

### Phase 3 Success
- [ ] GDS plugin installs and functions
- [ ] Bloom plugin accessible
- [ ] Monitoring metrics flowing to Azure Monitor
- [ ] Backup and restore procedures documented and tested

### Phase 4 Success
- [ ] CNAB bundle passes Azure Marketplace certification
- [ ] Offer live in Azure Marketplace
- [ ] Documentation complete and published
- [ ] Support and maintenance procedures established

---

## Timeline Summary

| Phase | Duration | Key Milestones |
|-------|----------|----------------|
| Phase 1: Helm Integration | 2 weeks | Standalone deployment working |
| Phase 2: Clustering | 2 weeks | 3 and 5 node clusters operational |
| Phase 3: Advanced Features | 2 weeks | Plugins and monitoring integrated |
| Phase 4: Marketplace Certification | 2 weeks | Live in Azure Marketplace |
| **Total** | **6-8 weeks** | Production-ready AKS offering |

---

## Open Questions

1. **Helm Chart Version**: Which specific version of the Neo4j Helm chart should we target?
2. **Marketplace Pricing**: What pricing model for the AKS offering (BYOL only, or consumption-based)?
3. **Support Model**: What level of support will be provided for AKS deployments?
4. **Upgrade Path**: How will users upgrade from VM-based to AKS-based deployments?
5. **Multi-Region**: Will the initial release support multi-region deployments?

---

## Dependencies

- Neo4j Helm chart repository access
- Azure Partner Center account for Marketplace publishing
- Azure Container Registry for CNAB bundle hosting
- Microsoft Partner support for certification guidance
- Neo4j technical support for Helm chart questions

---

## Appendix: Configuration Mapping

### Bicep Parameter → Helm Value Mapping

| Current Bicep Parameter | Helm Chart Value | Notes |
|------------------------|------------------|-------|
| `nodeCount` | `neo4j.replicas` | Cluster size |
| `graphDatabaseVersion` | `neo4j.image.tag` | Neo4j version |
| `diskSize` | `volumes.data.requests.storage` | Persistent volume size |
| `adminPassword` | `neo4j.password` | Admin credentials |
| `licenseType` | `neo4j.acceptLicenseAgreement` | License acceptance |
| `installGraphDataScience` | `config.NEO4J_PLUGINS` | Plugin installation |
| `installBloom` | `config.NEO4J_PLUGINS` | Plugin installation |
| `userNodeSize` | `resources.requests/limits` | Pod resources |
| `kubernetesVersion` | AKS cluster version | Infrastructure layer |

---

## Conclusion

This migration to a Helm chart-based architecture aligns with both Microsoft Azure Marketplace requirements and Neo4j best practices. By leveraging official Neo4j Helm charts, we reduce maintenance burden, ensure compatibility with Neo4j 5.x clustering features, and enable Azure Marketplace certification.

The phased approach allows for incremental progress with clear success criteria at each stage, minimizing risk while delivering a production-ready Azure Marketplace offering.

**Next Steps:**
1. Review and approve this proposal
2. Allocate resources for Phase 1 implementation
3. Engage Microsoft Partner support for Marketplace guidance
4. Begin Phase 1 development

---

**Document Version**: 1.0
**Last Updated**: November 19, 2025
**Author**: Development Team
**Status**: Proposed
