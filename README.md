# Azure Neo4j Deployment

Infrastructure-as-code for deploying Neo4j on Azure using Bicep templates, published to the Azure Marketplace.

## Azure Marketplace

- [Neo4j Enterprise on Azure Marketplace](https://azuremarketplace.microsoft.com/en-us/marketplace/apps/neo4j.neo4j-ee)
- [Neo4j Community Edition on Azure Marketplace](https://azuremarketplace.microsoft.com/en-us/marketplace/apps/neo4j.neo4j-ce)

### Editions

| Edition | Template | VM | Disk | Nodes |
|---------|----------|-----|------|-------|
| **Enterprise** | `marketplace/neo4j-enterprise/` | VMSS (Standard_E4s_v5) | Premium_LRS | 1-10 |
| **Community** | `marketplace/neo4j-ce/` | Standalone VM (Standard_E4bds_v5, NVMe) | PremiumV2_LRS / Premium_LRS (auto) | 1 |

Both editions are built for production. The templates are architected so that database data is never lost, even when a VM is deleted or replaced by Azure during recovery.

### Enterprise Edition

Enterprise deploys a 1-to-10 node Neo4j cluster on a VM Scale Set. One node gives you a standalone instance. Three or more nodes form a cluster with Raft consensus, automatic failover, and data replication across members. The template wires up networking, load balancing, and cluster discovery so that Neo4j is operational once cloud-init finishes.

**How it works:**

- **VM Scale Set:** All nodes run in a VMSS with manual upgrade policy. Each instance gets a predictable public hostname (`vm{i}.neo4j-{uniqueString}.{location}.cloudapp.azure.com`) and a Premium_LRS data disk at LUN 0. Cloud-init formats the disk as XFS and mounts it at `/var/lib/neo4j`.
- **Load balancer (clusters only):** Deployments with 3+ nodes get a Standard SKU public load balancer that forwards Neo4j Browser (port 7474) and Bolt (port 7687) to the backend pool, with health probes on both ports. Single-node deployments skip the load balancer entirely and connect directly via the VM's public IP.
- **DNS-based cluster discovery:** Cluster members find each other through predictable internal hostnames, with no Azure CLI or API calls at runtime. Cloud-init generates the discovery endpoints (`node000000:6000,node000001:6000,...`) and configures Raft consensus (port 7000) and transaction shipping (port 6000) for Neo4j 5.x.
- **Network security:** A VNet (`10.0.0.0/8`) with NSG rules that open SSH (22), HTTP (7474), HTTPS (7473), Bolt (7687), and Bolt routing (7688) from the internet. Cluster communication ports (6000, 7000) are restricted to VNet-internal traffic only.
- **Managed identity:** A user-assigned managed identity is attached to the VMSS for Azure API access.
- **Cloud-init provisioning:** Separate cloud-init templates for standalone and cluster topologies handle Neo4j installation, APOC plugin setup, memory auto-tuning (`neo4j-admin server memory-recommendation`), admin password configuration (base64-encoded to avoid shell escaping issues), and cluster topology setup.

### Community Edition

Community Edition deploys a single Neo4j node on a standalone VM with a separate managed data disk. Database files live on their own disk, independent of the OS. If the VM is deleted, whether intentionally or by Azure during host recovery, the data disk survives. A replacement VM attaches the same disk via `createOption: Attach` and resumes with all data intact.

**How it works:**

- **Standalone VM:** A single `Microsoft.Compute/virtualMachines` resource. Azure's service healing automatically restarts standalone VMs on healthy hosts when hardware fails, providing the same single-instance availability guarantee as a VMSS without the abstraction overhead.
- **NVMe-first (Eds_v6 series):** Defaults to `Standard_E4ds_v6`, which uses NVMe exclusively. NVMe delivers higher remote disk throughput compared to SCSI at the same price point. The marketplace image supports both NVMe and SCSI (`DiskControllerTypes=SCSI,NVMe`), so overriding to a v5 size still works.
- **Trusted Launch:** Secure Boot + vTPM enabled on all VMs. Required by the marketplace image definition.
- **Separate managed data disk:** A `Microsoft.Compute/disks` resource (Premium_LRS) attached at LUN 0 with `deleteOption: Detach`. Cloud-init detects whether the disk is fresh or contains existing data and handles both cases.
- **No zone pinning:** All resources deploy without availability zone constraints, which means the template works with every VM SKU in every region. The tradeoff is losing `PremiumV2_LRS` tuneable IOPS, but universal compatibility wins for a marketplace template.
- **Accelerated networking:** SR-IOV hardware offload enabled on the NIC.
- **Network security:** A VNet with NSG rules that open SSH (22), HTTPS (7473), HTTP (7474), and Bolt (7687) from the internet.

**Why a separate disk:**

Inline VMSS data disks are destroyed when the instance is deleted or reimaged. A standalone `Microsoft.Compute/disks` resource has its own lifecycle, independent of the VM.

- **Data survives VM deletion.** When the VM is removed (intentionally or by Azure during recovery), the disk persists. A new VM attaches it via `createOption: Attach` and resumes with all data intact. This is the single most important architectural decision in the template.
- **Independent sizing.** Disk capacity is chosen separately from the VM size, so storage scales without changing the compute tier.
- **I/O isolation.** Database reads and writes don't compete with OS operations on the same physical disk.

See [CE Architecture](marketplace/neo4j-ce/ARCHITECTURE.md) for full details and design rationale.

## Repository Structure

```
marketplace/
  neo4j-enterprise/         # Enterprise edition (VMSS, load balancer)
  neo4j-ce/                 # Community Edition (standalone VM, NVMe, pickZones)
scripts/
  neo4j-enterprise/         # Enterprise cloud-init and provisioning
  neo4j-ce/cloud-init/      # CE cloud-init (standalone.yaml)
deployments/                # Deployment and testing CLI (see deployments/README.md)
test_suite/test_ce/         # CE integration tests (connectivity, CRUD, resilience)
.github/workflows/          # CI: enterprise.yml, community.yml
```

## Quick Start

### Deploy and Test

```bash
cd deployments

# First-time setup
uv run neo4j-deploy setup

# Deploy Enterprise standalone
uv run neo4j-deploy deploy --scenario standalone-lts

# Deploy Community Edition (region set during setup)
uv run neo4j-deploy deploy --scenario ce-standalone-latest

# Check status, test, clean up
uv run neo4j-deploy status
uv run neo4j-deploy test
uv run neo4j-deploy cleanup --all --force
```

See **[deployments/README.md](deployments/README.md)** for full command reference.

### Connecting to Neo4j

After deployment, find the FQDN and public IP for your instance:

```bash
# CE — show the VM's public IP and FQDN
az vm show --resource-group <resource-group> --name <vm-name> --show-details \
  --query '{publicIp: publicIps, fqdn: fqdns}' --output table
```

Then open Neo4j Browser at:

```
http://<fqdn>:7474
```

Connect with the Bolt driver at `neo4j://<fqdn>:7687`. The default username is `neo4j` and the password is the `adminPassword` set during deployment.

### Build Marketplace Packages

Before building, copy `.env.sample` to `.env` and set your Partner Center PIDs (GUIDs):

```bash
cp .env.sample .env
# Edit .env with your NEO4J_PARTNER_PID (Enterprise) and CE_NEO4J_PARTNER_PID (Community)
```

Then build:

```bash
cd deployments
uv run neo4j-deploy ee-package   # Enterprise
uv run neo4j-deploy ce-package   # Community Edition
```

## Requirements

- Azure CLI 2.50.0+ (includes Bicep CLI)
- Python 3.12+ with [uv](https://docs.astral.sh/uv/)
- Active Azure subscription

## Test Scenarios

| Scenario | Edition | Version | Purpose |
|----------|---------|---------|---------|
| `standalone-lts` | Enterprise Evaluation | LTS (5) | Single-node enterprise |
| `cluster-lts` | Enterprise Evaluation | LTS (5) | 3-node cluster |
| `ce-standalone-latest` | Community | CalVer (latest) | CE standalone (region set during setup, `pickZones` auto-adapts) |

## CE Integration Tests

The `test_suite/test_ce/` package runs integration tests against a deployed Community Edition instance.

**What it tests:**
- HTTP API and authenticated HTTP connectivity
- Bolt protocol connectivity
- APOC plugin availability
- Community Edition verification (`dbms.components()`)
- CRUD validation using a Movies graph dataset (The Matrix trilogy, 11+ nodes)
- VM provisioning and data disk attachment (full mode, via Azure SDK)
- Data persistence through a VM restart cycle (full mode)

**Running the tests:**

```bash
cd test_suite/test_ce

# Use the latest connection file (default)
uv run test-ce

# Use a specific connection file
uv run test-ce --results connection-ce-standalone-latest-20260207-212235.json

# Simple mode — connectivity + CRUD only, skips Azure resource checks
uv run test-ce --simple
```

Connection details and password are read from `deployments/.arm-testing/results/`. When `--results` is omitted the most recent connection file is used.

## CI/CD

GitHub Actions workflows validate deployments on pull requests:
- `enterprise.yml` - Enterprise standalone + cluster (LTS, Enterprise and Evaluation licenses)
- `community.yml` - Community Edition standalone

