#!/bin/bash
set -euo pipefail

# Deploy and validate all CE test scenarios.
# See TEST_CE.md for the full test plan.
#
# Usage:
#   ./deploy-ce-tests.sh              # Deploy all CE scenarios
#   ./deploy-ce-tests.sh --dry-run    # Preview only
#   ./deploy-ce-tests.sh --validate   # Skip deploy, run validation only

cd "$(dirname "$0")"

DRY_RUN=false
VALIDATE_ONLY=false

for arg in "$@"; do
  case "${arg}" in
    --dry-run)       DRY_RUN=true ;;
    --validate)      VALIDATE_ONLY=true ;;
    *)
      echo "Usage: $0 [--dry-run] [--validate]"
      exit 1
      ;;
  esac
done

CE_SCENARIOS=(
  ce-westus2-nvme
  ce-francecentral-nvme
  ce-germanywestcentral-scsi
  ce-southcentralus-scsi
  ce-westeurope-scsi
  ce-norwayeast-nvme
)

# ── Pre-compile Bicep ──────────────────────────────────────────────
# Compile main.bicep → main.json once before launching parallel deployments.
# The orchestrator skips recompilation when main.json is already up-to-date,
# avoiding a race where parallel processes delete each other's compiled output.
if ! ${VALIDATE_ONLY}; then
  BICEP_DIR="$(cd "$(dirname "$0")/../marketplace/neo4j-ce" && pwd)"
  echo "=== Pre-compiling Bicep template ==="
  az bicep build --file "${BICEP_DIR}/main.bicep"
  echo "  ✓ ${BICEP_DIR}/main.json"
  echo ""
fi

# ── Deploy ────────────────────────────────────────────────────────
if ! ${VALIDATE_ONLY}; then
  echo "=== Deploying ${#CE_SCENARIOS[@]} CE scenarios ==="
  echo ""

  DEPLOY_PIDS=()
  DEPLOY_LOGS=()

  for scenario in "${CE_SCENARIOS[@]}"; do
    LOG_FILE="/tmp/ce-deploy-${scenario}.log"
    echo "  Deploying: ${scenario} (log: ${LOG_FILE})"
    if ${DRY_RUN}; then
      uv run neo4j-deploy deploy -s "${scenario}" --dry-run > "${LOG_FILE}" 2>&1 &
    else
      uv run neo4j-deploy deploy -s "${scenario}" > "${LOG_FILE}" 2>&1 &
    fi
    DEPLOY_PIDS+=($!)
    DEPLOY_LOGS+=("${LOG_FILE}")
  done

  echo ""
  echo "  All ${#CE_SCENARIOS[@]} deployments launched. Waiting..."
  echo ""

  DEPLOY_FAILED=0
  for i in "${!DEPLOY_PIDS[@]}"; do
    scenario="${CE_SCENARIOS[$i]}"
    log="${DEPLOY_LOGS[$i]}"
    if wait "${DEPLOY_PIDS[$i]}"; then
      echo "  ✓ ${scenario} deployed"
    else
      echo "  ✗ ${scenario} DEPLOY FAILED (see ${log})"
      DEPLOY_FAILED=$((DEPLOY_FAILED + 1))
    fi
  done

  echo ""
  echo "=== Deploy: $((${#CE_SCENARIOS[@]} - DEPLOY_FAILED)) succeeded, ${DEPLOY_FAILED} failed ==="

  if ${DRY_RUN}; then
    echo ""
    echo "[dry-run] No resources were created."
    exit 0
  fi

  if [[ "${DEPLOY_FAILED}" -gt 0 ]]; then
    echo ""
    echo "Some deployments failed. Check logs above before running validation."
    echo "To validate the ones that succeeded: ./deploy-ce-tests.sh --validate"
    exit 1
  fi

  echo ""
fi

# ── Validate ──────────────────────────────────────────────────────
echo "=== Validating ${#CE_SCENARIOS[@]} CE scenarios ==="
echo ""

PIDS=()
LOGS=()

for scenario in "${CE_SCENARIOS[@]}"; do
  LOG_FILE="/tmp/ce-test-${scenario}.log"
  echo "  Validating: ${scenario} (log: ${LOG_FILE})"
  uv run validate_deploy "${scenario}" > "${LOG_FILE}" 2>&1 &
  PIDS+=($!)
  LOGS+=("${LOG_FILE}")
done

echo ""
echo "  All ${#CE_SCENARIOS[@]} validations launched. Waiting..."
echo ""

FAILED=0
for i in "${!PIDS[@]}"; do
  scenario="${CE_SCENARIOS[$i]}"
  log="${LOGS[$i]}"
  if wait "${PIDS[$i]}"; then
    echo "  ✓ ${scenario} passed"
  else
    echo "  ✗ ${scenario} FAILED (see ${log})"
    FAILED=$((FAILED + 1))
  fi
done

echo ""
echo "=== Validation: $((${#CE_SCENARIOS[@]} - FAILED)) passed, ${FAILED} failed ==="

if [[ "${FAILED}" -gt 0 ]]; then
  echo ""
  echo "Failed test logs:"
  for i in "${!PIDS[@]}"; do
    log="${LOGS[$i]}"
    if ! wait "${PIDS[$i]}" 2>/dev/null; then
      echo "  ${log}"
    fi
  done
  exit 1
fi

echo ""
echo "All scenarios passed! Next steps:"
echo "  ./shutdown.sh  # Clean up all resources"
