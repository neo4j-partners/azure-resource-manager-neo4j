# Neo4j Enterprise on Azure Kubernetes Service (AKS)

Deploy Neo4j Enterprise Edition on Azure Kubernetes Service using Bicep templates and the official Neo4j Helm chart.

## Overview

This deployment provides a modern, cloud-native alternative to VM-based Neo4j deployments, offering:

- **Kubernetes-native architecture** with StatefulSets and Persistent Volumes
- **Official Neo4j Helm chart** for best-practice configuration
- **Automatic scaling** with AKS node pools
- **Azure integration** for monitoring, storage, and identity
- **Production-ready** security and high availability options

**Deployment Time:** 15-20 minutes
**Supported Versions:** Neo4j 5.x Enterprise
**Architecture:** Bicep (Infrastructure) + Helm (Application)

## Quick Start

### Deploy Standalone Instance

```bash
./deploy.sh my-resource-group
```

This deploys:
- AKS cluster with managed Kubernetes
- Neo4j Enterprise 5.x (standalone)
- Premium SSD persistent storage
- External LoadBalancer for access

**After deployment**, connect to Neo4j:
- **Neo4j Browser:** `http://<external-ip>:7474`
- **Bolt URI:** `neo4j://<external-ip>:7687`
- **Username:** `neo4j`
- **Password:** From deployment parameters

### Custom Deployment

```bash
az deployment group create \
  --resource-group my-neo4j-rg \
  --template-file main.bicep \
  --parameters nodeCount=3 \
               graphDatabaseVersion="5" \
               adminPassword="SecurePassword123!" \
               licenseType="Evaluation"
```

## What Gets Deployed

**Azure Resources:**
- AKS Cluster (Kubernetes 1.30+)
- Virtual Network with subnets
- Managed Identity for Workload Identity
- Premium SSD storage class
- Azure Monitor & Container Insights
- LoadBalancer with public IP

**Kubernetes Resources** (via Helm):
- Neo4j StatefulSet with persistent volumes
- Services (headless + LoadBalancer)
- ConfigMaps and Secrets
- RBAC roles and service accounts

**Result:** Fully functional Neo4j cluster accessible via public IP.

## Deployment Scenarios

| Scenario | Description | Parameters |
|----------|-------------|------------|
| **Standalone** | Single Neo4j instance | `nodeCount=1` |
| **Cluster** | High availability (3-10 nodes) | `nodeCount=3` |
| **Custom Storage** | Larger data volumes | `diskSize=128` |
| **Enterprise VM** | Larger compute | `userNodeSize="Standard_E8s_v5"` |

## Documentation

### Getting Started
- **[Getting Started Guide](GETTING-STARTED.md)** - Complete deployment walkthrough
- **[Troubleshooting](TROUBLESHOOTING.md)** - Common issues and solutions

### Reference
- **[Architecture](ARCHITECTURE.md)** - Detailed system design
- **[Parameter Reference](docs/REFERENCE.md)** - All configuration options
- **[Cluster Discovery](docs/CLUSTER-DISCOVERY.md)** - Resolver types explained

### Operations
- **[Operations Guide](docs/OPERATIONS.md)** - Day-2 operations (monitoring, backup, scaling)

### Development
- **[Development Guide](docs/development/DEVELOPMENT.md)** - Contributing to templates
- **[Helm Integration](docs/development/HELM-INTEGRATION.md)** - Technical implementation details

## Prerequisites

- **Azure CLI** (`az`) version 2.50.0+
- **kubectl** version 1.28+
- **Bicep** version 0.20.0+ (bundled with Azure CLI)
- **Active Azure subscription** with Contributor access
- **Quotas:** ~10 vCPUs for Standard_D/E series VMs

## Key Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `nodeCount` | int | 1 | Neo4j instances (1, 3-10) |
| `graphDatabaseVersion` | string | "5" | Neo4j version |
| `adminPassword` | securestring | (required) | Admin password |
| `licenseType` | string | "Evaluation" | "Enterprise" or "Evaluation" |
| `diskSize` | int | 32 | Storage size in GB |
| `userNodeSize` | string | "Standard_E4s_v5" | AKS node VM size |

**See [Parameter Reference](docs/REFERENCE.md) for complete list.**

## Cost Estimation

Approximate monthly costs for standalone deployment (East US):

| Resource | Configuration | Monthly Cost |
|----------|---------------|--------------|
| AKS Management | Managed service | **Free** |
| System Node Pool | 3x Standard_D2s_v5 | ~$250 |
| User Node Pool | 1x Standard_E4s_v5 | ~$240 |
| LoadBalancer | Standard | ~$20 |
| Storage | 32GB Premium SSD | ~$5 |
| **Total** | | **~$515/month** |

*Costs scale with additional Neo4j nodes and larger VM sizes.*

## Architecture Highlights

**Infrastructure** (Bicep):
- Provisions AKS cluster, networking, identity, storage
- Configures Azure Monitor integration
- Sets up Workload Identity for secure access

**Application** (Helm):
- Uses official Neo4j Helm chart (`neo4j/neo4j` v5.24.0)
- Deploys Neo4j as Kubernetes StatefulSet
- Configures persistent storage, services, and secrets
- Handles cluster formation and discovery

**See [ARCHITECTURE.md](ARCHITECTURE.md) for detailed design.**

## Cleanup

Delete all deployed resources:

```bash
./delete.sh my-resource-group
```

Or manually:

```bash
az group delete --name my-resource-group --yes
```

## Getting Help

**Documentation:**
1. [Getting Started Guide](GETTING-STARTED.md) - First-time deployment
2. [Troubleshooting](TROUBLESHOOTING.md) - Common issues
3. [Neo4j Kubernetes Docs](https://neo4j.com/docs/operations-manual/5/kubernetes/)

**Support:**
- **GitHub Issues:** https://github.com/neo4j-partners/azure-resource-manager-neo4j/issues
- **Neo4j Community:** https://community.neo4j.com
- **Neo4j Support:** support@neo4j.com (Enterprise customers)

## Related Deployments

Looking for different deployment options?

- **VM-based deployment:** See `marketplace/neo4j-enterprise/`
- **Community Edition:** See `marketplace/neo4j-community/`

## License

Neo4j Enterprise Edition requires a valid license. This deployment supports:
- **Enterprise License:** Production use with valid license key
- **Evaluation License:** 30-day trial for testing (no license key required)

---

**Template Version:** 1.0 (Bicep + Helm)
**Last Updated:** November 2025
**Maintained by:** Neo4j Partners Team
