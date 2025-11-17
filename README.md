# Azure Neo4j Deployment - Bicep Modernization

This repository contains modernized infrastructure-as-code for deploying Neo4j on Azure, migrating from ARM JSON templates to Azure Bicep.

## Overview

This project modernizes the Neo4j Azure deployment infrastructure with:

- **Azure Bicep** - Modern, declarative infrastructure-as-code replacing ARM JSON
- **Cloud-Init** - Declarative VM provisioning replacing complex bash scripts
- **Key Vault Integration** - Secure secret management with VM Managed Identity
- **Automated Linting** - Quality and security validation via Bicep linter
- **Simplified Architecture** - Clean, maintainable templates without over-engineering

## Repository Structure

```
├── bicepconfig.json                 # Bicep linter configuration
├── marketplace/
│   ├── neo4j-enterprise/           # Enterprise edition templates
│   └── neo4j-community/            # Community edition templates
├── scripts/
│   ├── neo4j-enterprise/           # Enterprise installation scripts (being modernized)
│   ├── neo4j-community/            # Community installation scripts (being modernized)
│   ├── pre-commit-bicep            # Git pre-commit hook for Bicep validation
│   ├── install-git-hooks.sh        # Hook installation script
│   └── validate-environment.sh     # Development environment validation
└── docs/
    ├── BICEP_STANDARDS.md          # Bicep development standards and conventions
    ├── DEVELOPMENT_SETUP.md        # Development environment setup guide
    └── MODERNIZE_PLAN_V2.md        # Complete modernization plan
```

## Quick Start for Developers

### 1. Install Required Tools

See [docs/DEVELOPMENT_SETUP.md](docs/DEVELOPMENT_SETUP.md) for detailed installation instructions.

**Required:**
- Azure CLI 2.50.0+
- Bicep CLI 0.20.0+ (bundled with Azure CLI)
- Git 2.30.0+

**Recommended:**
- Visual Studio Code with Bicep extension

### 2. Verify Your Environment

```bash
# Run the validation script
./scripts/validate-environment.sh
```

This checks that all required tools are installed and configured correctly.

### 3. Install Git Hooks

```bash
# Install pre-commit hook for Bicep validation
./scripts/install-git-hooks.sh
```

The pre-commit hook automatically validates Bicep files before commits.

### 4. Review Development Standards

Read [docs/BICEP_STANDARDS.md](docs/BICEP_STANDARDS.md) to understand:
- Bicep coding standards and conventions
- Naming conventions
- Security best practices
- Linter configuration

## Modernization Status

This repository is currently undergoing modernization from ARM JSON to Bicep. See [docs/MODERNIZE_PLAN_V2.md](docs/MODERNIZE_PLAN_V2.md) for the complete modernization plan.

### Completed (Phase 1)

- ✅ Bicep linter configuration
- ✅ Pre-commit hook for validation
- ✅ Development standards documentation
- ✅ Environment setup guide
- ✅ Validation tooling

### Completed (Phase 2 - Enterprise Edition)

- ✅ Enterprise ARM JSON to Bicep migration
- ✅ Bicep template compilation and validation (zero errors/warnings)
- ✅ Removed _artifactsLocation pattern, using direct GitHub URLs
- ✅ Updated deployment and archive scripts for Bicep workflow

### In Progress

- 🔄 Phase 2: Testing Enterprise Bicep deployments
- 🔄 Phase 2.5: Community Edition Bicep migration
- 🔄 Phase 3: Cloud-init integration
- 🔄 Phase 4: Key Vault with Managed Identity
- 🔄 Phase 5: Resource tagging
- 🔄 Phase 6: Final validation

## Deployment

### Enterprise Edition (Bicep)

The Enterprise edition now uses Bicep templates:

```bash
cd marketplace/neo4j-enterprise
./deploy.sh <resource-group-name>
```

The deployment script will:
1. Create the resource group
2. Compile Bicep to ARM JSON
3. Deploy using Azure CLI
4. Display deployment status and outputs

**For marketplace publishing:**
```bash
cd marketplace/neo4j-enterprise
./makeArchive.sh
```

This generates `archive.zip` containing the compiled ARM template ready for Azure Marketplace.

### Community Edition (Coming Soon)

Community edition Bicep migration is planned for Phase 2.5:

```bash
cd marketplace/neo4j-community
./deploy.sh <resource-group-name>
```

## Azure Marketplace

The templates in this repository are used for:
- [Neo4j Enterprise on Azure Marketplace](https://azuremarketplace.microsoft.com/en-us/marketplace/apps/neo4j.neo4j-ee)
- [Neo4j Community on Azure Marketplace](https://azuremarketplace.microsoft.com/en-us/marketplace/apps/neo4j.neo4j-community)

## Key Features

### Neo4j Enterprise

- Standalone (1 node) or cluster (3-10 nodes) deployments
- Optional read replicas (0-10)
- Neo4j versions 5.x and 4.4 support
- Graph Data Science and Bloom plugins
- Enterprise and Evaluation license types

### Neo4j Community

- Standalone deployment
- Neo4j version 5.x support

## Documentation

- [Development Setup Guide](docs/DEVELOPMENT_SETUP.md) - Environment setup instructions
- [Bicep Standards](docs/BICEP_STANDARDS.md) - Coding standards and best practices
- [Bicep Migration Notes](docs/BICEP_MIGRATION.md) - ARM to Bicep migration details and architecture
- [Modernization Plan](MODERNIZE_PLAN_V2.md) - Complete modernization roadmap

## Contributing

### Before You Start

1. Read [docs/DEVELOPMENT_SETUP.md](docs/DEVELOPMENT_SETUP.md) for environment setup
2. Review [docs/BICEP_STANDARDS.md](docs/BICEP_STANDARDS.md) for coding standards
3. Run `./scripts/validate-environment.sh` to verify your setup
4. Install git hooks with `./scripts/install-git-hooks.sh`

### Development Workflow

1. Create a feature branch
2. Make changes following Bicep standards
3. Run `az bicep build` to validate your changes
4. Commit (pre-commit hook will validate automatically)
5. Submit pull request

### Code Quality

All Bicep code must:
- Pass Bicep linter with zero errors
- Follow naming conventions in BICEP_STANDARDS.md
- Include parameter descriptions
- Not contain hardcoded secrets
- Use secure parameters with `@secure()` decorator
- Apply resource tags

## Security

This modernization prioritizes security:

- **No secrets in code** - All secrets managed via Azure Key Vault
- **Managed Identity** - VMs use managed identity to access Key Vault
- **Linter enforcement** - Security rules enforced at build time
- **Secure parameters** - `@secure()` decorator required for sensitive data
- **Output validation** - Prevents secret exposure in template outputs

## Support

For issues or questions:
- Check [docs/DEVELOPMENT_SETUP.md](docs/DEVELOPMENT_SETUP.md) troubleshooting section
- Review [docs/BICEP_STANDARDS.md](docs/BICEP_STANDARDS.md) for standards
- Consult [Azure Bicep documentation](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- Open an issue in this repository

## License

See LICENSE file for details.

---

**Status:** Under active modernization
**Last Updated:** 2025-11-16
**Current Phase:** Phase 2 Enterprise Edition Complete (Templates & Scripts), Testing in Progress
