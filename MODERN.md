# Proposal for Modernizing the Neo4j Enterprise ARM Deployment for 2025

**Date:** 2025-11-16 17:24:33  
**Author:** retroryan

## 1. Introduction

This document outlines a proposal to modernize the deployment process for the Neo4j Enterprise solution located in `marketplace/neo4j-enterprise/`. The current deployment relies on linked ARM JSON templates, `_artifactsLocation` patterns, and manual parameter file creation. These can be improved by adopting 2025 best practices for Azure Infrastructure as Code (IaC), focusing on security, maintainability, marketplace readiness, and developer experience.

## 2. Core Modernization Recommendations

### Recommendation 1: Migrate ARM JSON to Bicep

**What:** Decompile existing `mainTemplate.json` and all nested/linked templates into `.bicep` using `az bicep decompile`, then refactor.

**Why:**
- Human-readable, concise syntax.
- Built-in type validation and linting.
- Native module system (replaces linked templates + `_artifactsLocation`).
- Easier evolution and onboarding of contributors.

### Recommendation 2: Refactor to Native Bicep Modules

**What:** Split infrastructure concerns: e.g. `network.bicep`, `compute.bicep`, `storage.bicep`, `neo4jCluster.bicep`, `monitoring.bicep`.

**Why:**
- Clear separation of concerns and testability.
- Dependency graph clarity (module outputs/inputs).
- Eliminates artifact staging + SAS token complexity for local and CI deployments.

### Recommendation 3: Secure Secret Management via Azure Key Vault

**What:** Replace inline password parameters with Key Vault secret references. Script logic ensures a secret exists (create if missing) and passes only object IDs / secret names to Bicep.

**Why:**
- Secrets never written to disk or stored in Git.
- Centralized rotation & auditing.
- Compatible with Enterprise Zero Trust patterns.

### Recommendation 4: Standardized Resource Tagging

**What:** Define and enforce tags applied uniformly to every resource (either via a module wrapper or a common tags variable).

**Candidate Tag Set:**
- `Project`: `Neo4j-Enterprise`
- `Environment`: (parameter: `dev` / `test` / `prod`)
- `DeploymentDateUTC`: (script-generated current UTC date)
- `TemplateVersion`: (hard-coded or module output, e.g. `2.0.0`)
- `DeployedBy`: (Azure CLI logged-in user principal name)
- `CostCenter`: (optional parameter)
- `Compliance`: `true` (or policy reference if required)

**Why:**
- Improves cost analysis, lifecycle management, and policy assignment.
- Enables governance teams to filter or report consistently.

### Recommendation 5: Publish as Template Specs for Internal Reuse

**What:** After building Bicep to JSON, publish final template to an Azure Template Spec per version (e.g. `neo4j-enterprise/2.0.0`).

**Why:**
- Controlled distribution channel with RBAC.
- Immutable versions; easy rollback.
- Consumers deploy via Template Spec ID rather than cloning source.

### Recommendation 6: Integrate `what-if` and ARM Template Test Toolkit (arm-ttk)

**What:** Automate pre-deployment validation steps in CI:
- Run `az deployment sub what-if` / `group what-if` in pipeline.
- Run `arm-ttk` against compiled ARM JSON artifacts for lint/best practice compliance.

**Why:**
- Early detection of breaking changes.
- Enforces standards consistently.

### Recommendation 7: Introduce Bicep Linter + Git Hooks

**What:**
- Enable Bicep linter with a configuration file (e.g. `.bicepconfig.json`) tuned for required rules.
- Optionally add a pre-commit hook to run `bicep build` + linter.

**Why:**
- Ensures all commits maintain structural quality.
- Reduces review burden.

### Recommendation 8: CI/CD Enhancements

**Pipeline Stages:**
1. Validate: Lint Bicep, run `bicep build`, run arm-ttk.
2. Security: Check for accidental plain-text secrets, verify Key Vault references.
3. What-If: Dry run against test subscription/resource group.
4. Deploy (Non-Prod): Execute deployment, smoke test (e.g., confirm Neo4j bolt port responds).
5. Promote: Optionally publish Template Spec or create Marketplace package.

**Why:**
- Repeatable, auditable releases.
- Separation of validation from execution.

### Recommendation 9: Observability and Post-Deployment Health Checks

**What:** Add optional modules for:
- Azure Monitor diagnostic settings.
- Log Analytics workspace linkage.
- Alerts (e.g., VM CPU, Disk I/O, Neo4j service availability).

**Why:**
- Production readiness.
- Facilitates SLA monitoring.

### Recommendation 10: Policy and Guardrails Integration

**What:** Reference existing Azure Policy initiatives (if organization-managed) OR provide sample policy assignment module (e.g. restricting allowed locations, enforcing tags, requiring Key Vault usage).

**Why:**
- Prevents drift from compliance baselines.
- Encourages secure defaults.

## 3. Script Modernization (Deployment Orchestrator)

The Python deployment helper (previously described in LOCAL_TESTING.md) should be modernized to:

1. Parse Bicep parameters and generate a temporary parameters file only if necessary (favor direct CLI parameter passing for non-secret values).
2. Verify login and subscription context (`az account show`).
3. Ensure resource group exists (create if absent).
4. Manage Key Vault secret lifecycle.
5. Inject a standard tag set dynamically (pass as a single JSON object parameter).
6. Execute `az bicep build` and capture version metadata.
7. Run `what-if` and prompt for confirmation.
8. Optionally publish Template Spec (`az ts create/update`).
9. Optionally output a Marketplace-ready compiled artifact bundle (see Section 4).
10. Provide a simple post-deployment verification (e.g., run a Neo4j connectivity check using bolt driver—description only, no code).

All done with clear logging, dry-run mode, and non-zero exit codes on failure.

## 4. Aligning with the Azure Marketplace Publishing Process (Bicep Path)

**Marketplace Artifact Requirements:**
- `mainTemplate.json`: Primary ARM template.
- `createUiDefinition.json`: Portal UI definition controlling user input.
- Optional supporting docs (e.g. `README`, legal terms).

**Modern Flow Using Bicep:**
1. Author modular infrastructure in Bicep locally.
2. Produce a single compiled `mainTemplate.json` via `az bicep build`.
3. Validate compiled template (lint + arm-ttk).
4. Package: Zip `mainTemplate.json` + `createUiDefinition.json` + legal + marketing assets.
5. Submit via Marketplace publishing portal or Partner Center pipeline.
6. For updates: Increment internal `TemplateVersion`, rebuild, re-run compliance validations, republish.

**Advantages:**
- No runtime dependency on `_artifactsLocation` or SAS tokens for linked template resolution.
- Reduced surface for storage misconfiguration.
- Clear delineation between authoring (Bicep) and distribution (compiled JSON).

**Important Considerations:**
- Keep parameter names stable; Marketplace UI maps to them.
- Use descriptive `metadata` for parameters—improves user clarity in Portal.
- Avoid dynamic generation of resource types not allowed by Marketplace certification (e.g. disallowed preview SKUs).
- Ensure idempotence: Re-deploy with same parameters should not error.

## 5. Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Complex migration of existing JSON | Incremental: decompile one segment at a time, validate parity via what-if diffs |
| Secret mismanagement during transition | Mandate Key Vault integration before removing old password parameters |
| Drift between Bicep and published JSON | CI auto-build and diff check; fail pipeline if uncommitted JSON artifact differs |
| Marketplace certification delays | Early validation against Marketplace checklist + test offers in sandbox |

## 6. Versioning Strategy

- Maintain a `VERSION` file or a `param` in root Bicep (e.g. `param templateVersion string = '2.0.0'`).
- Tag Git releases (`v2.0.0`, etc.).
- Align Template Spec versions with semantic version tags.
- Include `TemplateVersion` tag on every resource for traceability.

## 7. Governance & Policy Integration

Optionally add a `policy.bicep` module that:
- Assigns tag enforcement policies.
- Restricts locations based on `allowedLocations` parameter.
- Requires diagnostic settings for compute and storage.

This module can be conditional (parameter toggle).

## 8. Future Enhancements

- Migrate from manual script to GitHub Action workflow with OIDC federation (no PAT or service principal secret).
- Add automated load test harness for Neo4j cluster after deployment (description-only initially).
- Provide a Marketplace “Try Now” lightweight variant (single-node) using a separate minimal Bicep entry point.

## 9. Summary

By moving to Bicep, embracing Key Vault, enforcing tagging, validating with what-if + arm-ttk, and integrating Template Specs plus Marketplace packaging, the Neo4j Enterprise deployment becomes more secure, maintainable, and aligned with 2025 Azure IaC best practices.

---

## 10. Action Checklist

| Action | Owner | Status |
|--------|-------|--------|
| Decompile existing JSON to Bicep | Infra team | Pending |
| Refactor into modules | Infra team | Pending |
| Implement Key Vault secret flow | Script author | Pending |
| Add tag injection | Script author | Pending |
| Set up CI (lint, build, what-if) | DevOps | Pending |
| Publish first Template Spec (beta) | DevOps | Pending |
| Prepare Marketplace ZIP from compiled JSON | Release mgmt | Pending |
| Add observability module | Infra team | Pending |

## 11. References (Conceptual)

- Azure Bicep documentation (design & modules)
- Azure Marketplace publishing guidelines (offer + technical configuration)
- ARM Template Test Toolkit
- Azure Key Vault secret reference patterns
- What-If deployment feature for safe change previews
