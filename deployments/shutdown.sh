#!/bin/bash
set -euo pipefail

# Delete all test resource groups (CE + EE scenarios) for a clean slate.
# Uses the neo4j-deploy CLI state first, then sweeps for any orphaned
# resource groups matching the naming prefix.
#
# Usage:
#   ./shutdown.sh              # Interactive — prompts before deleting
#   ./shutdown.sh --force      # Skip prompts
#   ./shutdown.sh --dry-run    # Preview only

cd "$(dirname "$0")"

FORCE=false
DRY_RUN=false

for arg in "$@"; do
  case "${arg}" in
    --force|-f) FORCE=true ;;
    --dry-run)  DRY_RUN=true ;;
    *)
      echo "Usage: $0 [--force] [--dry-run]"
      exit 1
      ;;
  esac
done

RG_PREFIX="neo4j-test"

echo "=== Neo4j Test Environment Shutdown ==="
echo ""

# ── Step 1: CLI-tracked deployments ──────────────────────────────
echo "Step 1: Cleaning up CLI-tracked deployments..."

CLI_FLAGS="--all"
if ${FORCE}; then CLI_FLAGS="${CLI_FLAGS} --force"; fi
if ${DRY_RUN}; then CLI_FLAGS="${CLI_FLAGS} --dry-run"; fi

# shellcheck disable=SC2086
uv run neo4j-deploy cleanup ${CLI_FLAGS} 2>/dev/null || true

echo ""

# ── Step 2: Sweep for orphaned resource groups ───────────────────
echo "Step 2: Checking for orphaned resource groups (prefix: ${RG_PREFIX})..."

ORPHANS=$(az group list \
  --query "[?starts_with(name, '${RG_PREFIX}')].{name:name, location:location}" \
  --output tsv 2>/dev/null || true)

if [[ -z "${ORPHANS}" ]]; then
  echo "  No orphaned resource groups found."
else
  echo ""
  echo "  Found resource groups:"
  while IFS=$'\t' read -r name location; do
    echo "    ${name}  (${location})"
  done <<< "${ORPHANS}"
  echo ""

  if ${DRY_RUN}; then
    echo "  [dry-run] Would delete the above resource groups."
  else
    if ! ${FORCE}; then
      read -rp "  Delete all of the above resource groups? [y/N] " confirm
      if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
        echo "  Skipped."
        echo ""
        echo "=== Shutdown cancelled ==="
        exit 0
      fi
    fi

    PIDS=()
    NAMES=()
    while IFS=$'\t' read -r name _location; do
      echo "  Deleting: ${name} (--no-wait)"
      az group delete --name "${name}" --yes --no-wait &
      PIDS+=($!)
      NAMES+=("${name}")
    done <<< "${ORPHANS}"

    # Wait for delete commands to submit (they return quickly with --no-wait)
    for i in "${!PIDS[@]}"; do
      if wait "${PIDS[$i]}"; then
        echo "    ✓ ${NAMES[$i]} deletion started"
      else
        echo "    ✗ ${NAMES[$i]} failed to start deletion"
      fi
    done
  fi
fi

# ── Step 3: Clean up the validation temp RG ──────────────────────
VALIDATION_RG="arm-validation-temp"
if az group show --name "${VALIDATION_RG}" &>/dev/null; then
  echo ""
  echo "Step 3: Deleting validation resource group: ${VALIDATION_RG}"
  if ${DRY_RUN}; then
    echo "  [dry-run] Would delete ${VALIDATION_RG}."
  else
    az group delete --name "${VALIDATION_RG}" --yes --no-wait
    echo "  ✓ ${VALIDATION_RG} deletion started"
  fi
else
  echo ""
  echo "Step 3: No validation resource group found (${VALIDATION_RG})."
fi

echo ""
echo "=== Shutdown complete ==="
echo ""
echo "Resource group deletions run asynchronously. Check progress with:"
echo "  az group list --query \"[?starts_with(name, '${RG_PREFIX}')].name\" -o tsv"
