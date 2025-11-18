# Local Tests Dependency Review

**Review Date**: 2025-11-17
**Current Bicep CLI**: v0.39.26 (upgraded today ✅)
**Python Version**: 3.13 (specified in venv)

---

## Executive Summary

✅ **Bicep Integration**: Uses latest Bicep CLI automatically via `az deployment group create`
⚠️ **Python Dependencies**: Need 2 updates (1 critical deprecation)

---

## 1. Bicep CLI Integration ✅

### How It Works

The test framework uses Bicep templates directly without pre-compilation:

```python
# From src/orchestrator.py
command = (
    f"az deployment group create "
    f"--template-file {template_path} "  # Passes .bicep file directly
    f"--parameters {params_path} "
)
```

**Azure CLI automatically compiles Bicep files** when deploying, using whatever version is installed via `az bicep`.

### Current Status

- ✅ **Bicep CLI v0.39.26** (latest, upgraded 2025-11-17)
- ✅ **Auto-compilation** happens during deployment
- ✅ **Latest type definitions** available (2025-01-01 API versions)
- ✅ **No manual compilation** required in test framework

**Conclusion**: Bicep integration is already using the latest version. No changes needed.

---

## 2. Python Dependencies Review

### Current Dependencies (pyproject.toml)

```toml
dependencies = [
    "gitpython>=3.1.45",
    "neo4j-driver>=5.28.2",      # ⚠️ DEPRECATED PACKAGE NAME
    "pydantic>=2.12.4",
    "pyyaml>=6.0.3",
    "requests>=2.32.5",
    "rich>=14.2.0",
    "typer>=0.20.0",
]
```

### Latest Versions Available (November 2025)

| Package | Current | Latest | Status | Notes |
|---------|---------|--------|--------|-------|
| gitpython | >=3.1.45 | 3.1.45 | ✅ Current | Latest stable |
| neo4j-driver | >=5.28.2 | 5.28.2 | 🔴 **DEPRECATED** | Use `neo4j` instead |
| pydantic | >=2.12.4 | 2.12.4 | ✅ Current | Latest stable |
| pyyaml | >=6.0.3 | 6.0.3 | ✅ Current | Latest stable |
| requests | >=2.32.5 | 2.32.5 | ✅ Current | Latest stable |
| rich | >=14.2.0 | 14.2.0 | ✅ Current | Latest stable |
| typer | >=0.20.0 | 0.20.0 | ✅ Current | Latest stable |

---

## 3. Critical Issue: neo4j-driver Deprecation 🔴

### Problem

The package `neo4j-driver` is **deprecated** and will receive no further updates starting with version 6.0.0.

**From PyPI**:
> "neo4j-driver is the old name for this package and is now deprecated and will receive no further updates starting with 6.0.0. Please install neo4j instead."

### Solution

Replace `neo4j-driver` with `neo4j`:

**Before**:
```toml
"neo4j-driver>=5.28.2",
```

**After**:
```toml
"neo4j>=5.28.2",
```

### Why This Matters

- `neo4j` is a **drop-in replacement** - no code changes needed
- Same API, same functionality
- Ensures future updates and security patches
- Prepares for Neo4j 6.0 release

### Migration Steps

1. Update `pyproject.toml`:
   ```toml
   dependencies = [
       "gitpython>=3.1.45",
       "neo4j>=5.28.2",          # Changed from neo4j-driver
       "pydantic>=2.12.4",
       "pyyaml>=6.0.3",
       "requests>=2.32.5",
       "rich>=14.2.0",
       "typer>=0.20.0",
   ]
   ```

2. Delete lock file and reinstall:
   ```bash
   cd localtests
   rm uv.lock
   uv sync
   ```

3. Verify installation:
   ```bash
   uv pip list | grep neo4j
   # Should show: neo4j 5.28.2
   ```

**No code changes required** - the `neo4j` package exports the same modules as `neo4j-driver`.

---

## 4. Optional: Upgrade to Neo4j 6.0

### Current

- Using: `neo4j>=5.28.2` (Python driver 5.x)
- Supports: Neo4j 4.4, 5.x

### Available

- Latest: `neo4j>=6.0.0` (Python driver 6.0)
- Supports: Neo4j 4.4, 5.x, 2025.x

### Recommendation

**For now, stay with 5.28.2** because:
- ✅ Current version is stable and tested
- ✅ Supports all Neo4j versions we're deploying (5.x, 4.4)
- ✅ No breaking changes in driver behavior

**Consider upgrading to 6.0** when:
- Testing Neo4j 2025.x deployments
- After driver 6.0 has been stable for a few months
- When you need new 6.0-specific features

---

## 5. Dependency Verification

### Check Current Installed Versions

```bash
cd localtests
uv pip list
```

### Check for Outdated Packages

```bash
cd localtests
uv pip list --outdated
```

### Update All Dependencies

```bash
cd localtests
uv sync --upgrade
```

---

## 6. Python Version Compatibility

### Current Python Version

The venv is using **Python 3.13** (as seen in `.venv/lib/python3.13/`)

### pyproject.toml Requirement

```toml
requires-python = ">=3.12"
```

**Status**: ✅ Compatible (3.13 >= 3.12)

### Package Compatibility with Python 3.13

All packages support Python 3.13:
- ✅ gitpython: Supports 3.13
- ✅ neo4j: Supports 3.7-3.13
- ✅ pydantic: Supports 3.8+
- ✅ pyyaml: Supports 3.6+
- ✅ requests: Supports 3.7+
- ✅ rich: Supports 3.8+
- ✅ typer: Supports 3.7+

**Conclusion**: All dependencies are compatible with Python 3.13.

---

## 7. GitHub Actions / CI/CD Considerations

### If Using GitHub Actions

Ensure the workflow uses the latest Bicep CLI:

```yaml
- name: Setup Bicep
  run: az bicep upgrade
```

Or pin to specific version:

```yaml
- name: Setup Bicep
  run: az bicep install --version v0.39.26
```

### If Using Azure DevOps

```yaml
- task: AzureCLI@2
  displayName: 'Upgrade Bicep'
  inputs:
    azureSubscription: '$(azureSubscription)'
    scriptType: 'bash'
    scriptLocation: 'inlineScript'
    inlineScript: 'az bicep upgrade'
```

---

## Recommended Actions

### Immediate (Before Next Deployment)

1. ✅ **Upgrade Bicep CLI** (Already done - v0.39.26)
2. 🔴 **Replace neo4j-driver with neo4j** in pyproject.toml
3. 🔴 **Reinstall dependencies** with `uv sync`

### Near-Term (This Week)

4. ⚠️ **Test deployments** with updated dependencies
5. ⚠️ **Update CI/CD pipelines** to use latest Bicep (if applicable)
6. ⚠️ **Document Python version requirement** (3.12+)

### Future Considerations

7. 📋 Consider upgrading to neo4j driver 6.0 when stable
8. 📋 Add dependabot or similar for automatic dependency updates
9. 📋 Pin exact versions for reproducible builds (remove >=)

---

## Summary

| Component | Status | Action Required |
|-----------|--------|-----------------|
| Bicep CLI | ✅ v0.39.26 | None - already latest |
| Bicep Integration | ✅ Auto-compile | None - working correctly |
| Python Version | ✅ 3.13 | None - compatible |
| neo4j-driver | 🔴 Deprecated | Replace with `neo4j` |
| Other Dependencies | ✅ Current | None - all up to date |

**Overall**: 1 critical update needed (package rename), everything else is current.

---

## References

- [Neo4j Python Driver Deprecation](https://pypi.org/project/neo4j-driver/)
- [Neo4j Python Driver 6.0 Docs](https://neo4j.com/docs/api/python-driver/current/)
- [Azure Bicep Releases](https://github.com/Azure/bicep/releases)
- [PyPI Package Search](https://pypi.org/)
