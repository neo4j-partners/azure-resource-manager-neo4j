# Changelog

All notable changes to the Neo4j on AKS Bicep templates.

## [1.0.0] - 2025-11-20

### Added
- **Bicep + Helm architecture** - Complete rewrite using official Neo4j Helm chart
- Comprehensive documentation structure with clear separation of concerns
- `GETTING-STARTED.md` - Complete deployment walkthrough
- `docs/REFERENCE.md` - Consolidated parameter reference
- `docs/CLUSTER-DISCOVERY.md` - Resolver types explained
- `docs/development/DEVELOPMENT.md` - Developer contribution guide
- `docs/development/HELM-INTEGRATION.md` - Helm technical reference
- Infrastructure modules: network, identity, aks-cluster, storage
- Application module: helm-deployment using official Neo4j chart (v5.24.0)
- Validation framework integration for automated testing

### Changed
- **Breaking:** Replaced custom Kubernetes resources with Helm chart deployment
- Helm chart version pinned to 5.24.0 for stability
- Documentation reorganized into logical hierarchy
- README.md slimmed down to focus on quick start

### Fixed
- Helm parameter mappings corrected (`volumes.data.dynamic.requests.storage`, `neo4j.resources.*`)
- Memory configuration using escaped dots instead of nested JSON
- Image configuration now uses chart defaults

### Removed
- Custom Bicep modules for Kubernetes resources (namespace, serviceaccount, configuration, statefulset, services)
- Neo4j 4.4 support (legacy, use Neo4j 5.x)
- Read replica support (deprecated in Neo4j 5.x)

## [0.x.x] - Historical

Previous implementation using custom Bicep Kubernetes resource modules.
See `docs/archive/CLEAN_HELM.md` for implementation history.

---

## Versioning

This project uses [Semantic Versioning](https://semver.org/):
- **MAJOR** version for incompatible API changes
- **MINOR** version for backwards-compatible functionality additions
- **PATCH** version for backwards-compatible bug fixes

## Contributing

See [DEVELOPMENT.md](DEVELOPMENT.md) for contribution guidelines.
