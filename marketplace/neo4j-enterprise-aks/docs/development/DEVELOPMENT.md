# Neo4j AKS Development Guide

Guide for developers contributing to the Neo4j on AKS Bicep templates.

## Overview

This deployment uses a **Bice

p + Helm architecture**:
- **Bicep** provisions Azure infrastructure (AKS, networking, storage)
- **Helm** deploys Neo4j application using official charts

## Development Environment Setup

### Required Tools

1. **Azure CLI** (2.50.0+)
   ```bash
   az --version
   az login --use-device-code
   ```

2. **Bicep CLI** (0.20.0+, bundled with Azure CLI)
   ```bash
   az bicep version
   az bicep upgrade
   ```

3. **kubectl** (1.28+)
   ```bash
   kubectl version --client
   ```

4. **Python 3.12+** with `uv` (for validation framework)
   ```bash
   python3 --version
   pip install uv
   ```

5. **Git**
   ```bash
   git --version
   ```

### Optional Tools

- **VS Code** with Bicep extension
- **Azure CLI extension** for AKS
  ```bash
  az extension add --name aks-preview
  ```

## Repository Structure

```
marketplace/neo4j-enterprise-aks/
├── main.bicep                    # Main orchestration template
├── parameters.json               # Default test parameters
├── deploy.sh                     # Local deployment script
├── delete.sh                     # Cleanup script
│
├── modules/                      # Bicep modules
│   ├── network.bicep             # VNet, subnets, NSG
│   ├── identity.bicep            # Managed identity
│   ├── aks-cluster.bicep         # AKS cluster + node pools
│   ├── storage.bicep             # StorageClass configuration
│   ├── neo4j-app.bicep           # Application orchestrator
│   └── helm-deployment.bicep     # Helm chart deployment
│
├── docs/                         # Documentation
│   ├── REFERENCE.md              # Parameter reference
│   ├── CLUSTER-DISCOVERY.md      # Resolver types
│   ├── development/              # Developer docs
│   ├── planning/                 # Roadmap
│   └── archive/                  # Historical docs
│
├── README.md                     # Main entry point
├── GETTING-STARTED.md            # Deployment guide
├── ARCHITECTURE.md               # System design
└── TROUBLESHOOTING.md            # Operations guide
```

### Module Responsibilities

#### Infrastructure Modules

**network.bicep**
- Creates Virtual Network (10.0.0.0/8)
- System subnet (10.0.0.0/16) for AKS
- User subnet (10.1.0.0/16) for Neo4j
- Network Security Group with Neo4j ports

**identity.bicep**
- User-assigned managed identity
- Used for Workload Identity in AKS

**aks-cluster.bicep**
- AKS cluster creation
- System node pool (3x Standard_D2s_v5, tainted)
- User node pool (autoscaling 1-10 nodes)
- Azure CNI networking
- Azure Monitor integration
- Workload Identity enablement

**storage.bicep**
- Creates Kubernetes StorageClass via deployment script
- Premium SSD configuration
- Volume expansion enabled
- Retain reclaim policy

#### Application Modules

**neo4j-app.bicep**
- Orchestrates Neo4j deployment
- Calls helm-deployment.bicep
- Passes parameters from main.bicep

**helm-deployment.bicep** ← **Key module**
- Uses Azure deployment script to run Helm
- Installs official Neo4j Helm chart (neo4j/neo4j v5.24.0)
- Maps Bicep parameters to Helm values
- Waits for deployment completion
- Extracts connection information

## Making Changes

### Development Workflow

1. **Create feature branch**
   ```bash
   git checkout -b feature/my-improvement
   ```

2. **Make changes** to Bicep files

3. **Compile and validate**
   ```bash
   cd marketplace/neo4j-enterprise-aks
   az bicep build --file main.bicep
   ```

4. **Test locally** (see Testing section below)

5. **Commit changes**
   ```bash
   git add .
   git commit -m "feat: description of change"
   ```

6. **Push and create PR**
   ```bash
   git push origin feature/my-improvement
   # Create pull request on GitHub
   ```

### Bicep Coding Standards

#### Style Guidelines

**Use latest API versions:**
```bicep
resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-02-01' = {
  // Not @2023-01-01 or preview versions
}
```

**Use parameter decorators:**
```bicep
@description('Number of Neo4j instances')
@minValue(1)
@maxValue(10)
param nodeCount int = 1
```

**Use symbolic references (not resourceId()):**
```bicep
// Good
subnets: [
  {
    id: userSubnet.id
  }
]

// Avoid
subnets: [
  {
    id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, subnetName)
  }
]
```

**Infer dependencies (avoid explicit dependsOn):**
```bicep
// Good - dependency inferred from parameter reference
module storage 'modules/storage.bicep' = {
  params: {
    aksClusterName: aksCluster.outputs.clusterName  // Implicit dependency
  }
}

// Avoid - explicit dependency
module storage 'modules/storage.bicep' = {
  params: {
    aksClusterName: aksCluster.outputs.clusterName
  }
  dependsOn: [
    aksCluster  // Unnecessary
  ]
}
```

#### Module Design

**Single responsibility:**
- Each module should do ONE thing well
- network.bicep handles networking, not storage

**Clear interfaces:**
- Parameters should be well-documented
- Outputs should be specific and typed

**No hardcoded values:**
- Use parameters or variables
- Make configuration flexible

#### Variable Naming

```bicep
// Good
var deploymentUniqueString = substring(uniqueString(resourceGroup().id), 0, 6)
var clusterName = '${resourceNamePrefix}-aks-${deploymentUniqueString}'

// Avoid
var unique = uniqueString(resourceGroup().id)  // Too generic
var name = '${prefix}-aks-${unique}'          // Ambiguous
```

### Helm Integration Guidelines

When modifying **helm-deployment.bicep**:

#### Critical Parameters

These parameter paths MUST be correct (from official Neo4j Helm chart):

```bash
# Storage - MUST use requests.storage
--set volumes.data.dynamic.requests.storage=32Gi

# Resources - MUST be under neo4j.resources
--set neo4j.resources.cpu=2000m
--set neo4j.resources.memory=8Gi

# Memory config - MUST escape dots
--set config.server\.memory\.heap\.initial_size=4G
```

**See [HELM-INTEGRATION.md](HELM-INTEGRATION.md) for complete reference.**

#### Testing Helm Changes

1. **Verify chart version exists:**
   ```bash
   helm search repo neo4j/neo4j --versions
   ```

2. **Test Helm command locally:**
   ```bash
   # Get AKS credentials
   az aks get-credentials --name <cluster> --resource-group <rg>

   # Test Helm install
   helm install neo4j-test neo4j/neo4j \
     --version 5.24.0 \
     --namespace neo4j-test \
     --create-namespace \
     --set neo4j.password=test123 \
     --set neo4j.edition=enterprise \
     --set neo4j.acceptLicenseAgreement=eval \
     --dry-run --debug
   ```

3. **Deploy via Bicep:**
   ```bash
   ./deploy.sh test-helm-changes
   ```

## Testing Changes

### Local Testing

#### Quick Test (Compile Only)

```bash
cd marketplace/neo4j-enterprise-aks
az bicep build --file main.bicep

# Check for errors
echo $?  # Should be 0
```

#### Full Deployment Test

```bash
# Deploy to test resource group
./deploy.sh my-test-deployment

# Verify deployment
az deployment group show \
  --resource-group my-test-deployment \
  --name main \
  --query "properties.provisioningState"

# Should return: "Succeeded"
```

#### Cleanup Test Environment

```bash
./delete.sh my-test-deployment
```

### Validation Framework Testing

The repository includes a comprehensive validation framework in `deployments/`.

#### Setup (One-Time)

```bash
cd deployments
uv run neo4j-deploy setup
```

#### Create Test Scenario

Edit `.arm-testing/config/scenarios.yaml`:

```yaml
scenarios:
  - name: test-my-feature
    deployment_type: aks
    node_count: 1
    graph_database_version: "5"
    kubernetes_version: "1.30"
    user_node_size: Standard_E4s_v5
    disk_size: 32
    license_type: Evaluation
```

#### Run Test

```bash
# Deploy scenario
uv run neo4j-deploy deploy --scenario test-my-feature

# Validate deployment
uv run neo4j-deploy test

# Or validate specific scenario
uv run validate_deploy test-my-feature

# Cleanup
uv run neo4j-deploy cleanup --deployment <id> --force
```

### Automated Testing (CI)

Deployments are automatically tested via GitHub Actions when PRs affect template files.

**Workflow:** `.github/workflows/aks.yml` (if exists)

Tests run:
1. Bicep compilation
2. Template deployment to test subscription
3. Validation suite execution
4. Automatic cleanup

## Common Development Tasks

### Adding a New Parameter

1. **Add to main.bicep:**
   ```bicep
   @description('My new parameter')
   param myNewParam string = 'default'
   ```

2. **Update parameters.json:**
   ```json
   {
     "myNewParam": {
       "value": "test-value"
     }
   }
   ```

3. **Pass to module:**
   ```bicep
   module neo4jApp 'modules/neo4j-app.bicep' = {
     params: {
       myNewParam: myNewParam
     }
   }
   ```

4. **Update helm-deployment.bicep** to use the parameter

5. **Update docs/REFERENCE.md** with parameter documentation

6. **Test end-to-end**

### Modifying Helm Integration

1. **Read the official chart docs:**
   https://github.com/neo4j/helm-charts

2. **Test Helm command manually** before adding to Bicep

3. **Update helm-deployment.bicep** script content

4. **Test deployment**

5. **Update docs/development/HELM-INTEGRATION.md**

### Adding a New Module

1. **Create module file:**
   ```bash
   touch modules/my-feature.bicep
   ```

2. **Define parameters and resources:**
   ```bicep
   @description('Parameter description')
   param myParam string

   resource myResource 'Microsoft.Service/resourceType@2024-01-01' = {
     name: 'resource-name'
     properties: {
       // ...
     }
   }

   output myOutput string = myResource.properties.someValue
   ```

3. **Call from main.bicep:**
   ```bicep
   module myFeature 'modules/my-feature.bicep' = {
     name: 'my-feature-deployment'
     params: {
       myParam: myParam
     }
   }
   ```

4. **Test and document**

## Debugging

### Bicep Compilation Errors

```bash
# Verbose compilation
az bicep build --file main.bicep --verbose

# Check specific module
az bicep build --file modules/helm-deployment.bicep
```

### Deployment Failures

```bash
# View deployment operations
az deployment group list-operations \
  --resource-group <rg-name> \
  --name main

# Show failed operations
az deployment operation group list \
  --resource-group <rg-name> \
  --name main \
  --query "[?properties.provisioningState=='Failed']"

# View deployment script logs (for Helm deployment)
az deployment-scripts show-log \
  --resource-group <rg-name> \
  --name helm-install-<unique-id>
```

### AKS/Kubernetes Issues

```bash
# Get AKS credentials
az aks get-credentials --name <cluster> --resource-group <rg>

# Check Helm releases
helm list -n neo4j

# Check Helm deployment logs
helm history neo4j -n neo4j

# View pod logs
kubectl logs neo4j-0 -n neo4j

# Describe pod for events
kubectl describe pod neo4j-0 -n neo4j

# Check deployment script status
az resource show \
  --ids <deployment-script-resource-id> \
  --query "properties.status"
```

## Submitting Changes

### Pull Request Checklist

Before submitting a PR:

- [ ] Bicep compiles without errors
- [ ] Tested deployment end-to-end
- [ ] Validation tests pass
- [ ] Documentation updated (README, REFERENCE, etc.)
- [ ] CHANGELOG entry added (if significant change)
- [ ] Commit messages follow convention (feat:, fix:, docs:, etc.)
- [ ] No hardcoded values or credentials
- [ ] Code follows style guidelines

### PR Description Template

```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update

## Testing
- [ ] Local deployment test passed
- [ ] Validation framework tests passed
- [ ] Manual testing completed

## Checklist
- [ ] Documentation updated
- [ ] No breaking changes (or documented)
- [ ] Follows coding standards
```

## Resources

- **Bicep Documentation:** https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/
- **AKS Documentation:** https://learn.microsoft.com/en-us/azure/aks/
- **Neo4j Helm Charts:** https://github.com/neo4j/helm-charts
- **Neo4j Kubernetes Docs:** https://neo4j.com/docs/operations-manual/5/kubernetes/

## Getting Help

- **GitHub Issues:** For bugs and feature requests
- **GitHub Discussions:** For questions and ideas
- **Neo4j Community:** https://community.neo4j.com

---

**Document Version:** 1.0
**Last Updated:** November 2025
