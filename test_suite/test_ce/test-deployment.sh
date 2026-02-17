#!/bin/bash
set -euo pipefail

# Test a CE marketplace deployment by fetching outputs from Azure,
# running a quick validation, then the full integration test suite.
#
# Usage:
#   ./test-deployment.sh <resource-group>
#
# Example:
#   ./test-deployment.sh my-rg

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <resource-group>"
  echo ""
  echo "Example:"
  echo "  $0 my-rg"
  exit 1
fi

RESOURCE_GROUP="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../.."
DEPLOYMENTS_DIR="${REPO_ROOT}/deployments"
RESULTS_DIR="${DEPLOYMENTS_DIR}/.arm-testing/results"

echo "=== CE Deployment Test ==="
echo "  Resource group: ${RESOURCE_GROUP}"
echo ""

# List deployments and let the user choose
echo "Fetching deployments..."
DEPLOYMENTS=$(az deployment group list \
  --resource-group "${RESOURCE_GROUP}" \
  --query "[].name" \
  --output tsv)

if [[ -z "${DEPLOYMENTS}" ]]; then
  echo "Error: No deployments found in resource group '${RESOURCE_GROUP}'."
  exit 1
fi

# Build numbered menu
DEPLOY_ARRAY=()
while IFS= read -r line; do
  DEPLOY_ARRAY+=("$line")
done <<< "${DEPLOYMENTS}"

echo ""
echo "Available deployments:"
for i in "${!DEPLOY_ARRAY[@]}"; do
  echo "  $((i + 1))) ${DEPLOY_ARRAY[$i]}"
done
echo ""

read -p "Select a deployment [1-${#DEPLOY_ARRAY[@]}]: " SELECTION

if [[ -z "${SELECTION}" ]] || [[ "${SELECTION}" -lt 1 ]] || [[ "${SELECTION}" -gt "${#DEPLOY_ARRAY[@]}" ]]; then
  echo "Error: Invalid selection."
  exit 1
fi

DEPLOYMENT_NAME="${DEPLOY_ARRAY[$((SELECTION - 1))]}"
echo ""
echo "  Selected: ${DEPLOYMENT_NAME}"
echo ""

# Prompt for password
read -s -p "Enter Neo4j admin password: " PASSWORD
echo ""
echo ""

# Fetch full deployment outputs
echo "Fetching deployment outputs..."
OUTPUTS_JSON=$(az deployment group show \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${DEPLOYMENT_NAME}" \
  --query "properties.outputs" \
  --output json)

if [[ -z "${OUTPUTS_JSON}" || "${OUTPUTS_JSON}" == "null" ]]; then
  echo "Error: Could not retrieve outputs from deployment."
  exit 1
fi

# Extract URLs from outputs
BOLT_URL=$(echo "${OUTPUTS_JSON}" | python3 -c "import sys,json; print(json.load(sys.stdin)['neo4jBoltURL']['value'])")
BROWSER_URL=$(echo "${OUTPUTS_JSON}" | python3 -c "import sys,json; print(json.load(sys.stdin)['neo4jBrowserURL']['value'])")

echo "  Bolt URL:    ${BOLT_URL}"
echo "  Browser URL: ${BROWSER_URL}"
echo ""

# Write connection file for the test suite
mkdir -p "${RESULTS_DIR}"
TIMESTAMP=$(date -u +"%Y%m%d-%H%M%S")
CONNECTION_FILE="connection-manual-${TIMESTAMP}.json"
CONNECTION_PATH="${RESULTS_DIR}/${CONNECTION_FILE}"

python3 -c "
import json, sys
outputs = json.loads(sys.argv[1])
conn = {
    'neo4j_uri': sys.argv[2],
    'browser_url': sys.argv[3],
    'username': 'neo4j',
    'password': sys.argv[4],
    'resource_group': sys.argv[5],
    'license_type': 'Community',
    'node_count': 1,
    'outputs': outputs,
}
with open(sys.argv[6], 'w') as f:
    json.dump(conn, f, indent=2)
" "${OUTPUTS_JSON}" "${BOLT_URL}" "${BROWSER_URL}" "${PASSWORD}" "${RESOURCE_GROUP}" "${CONNECTION_PATH}"

echo "  Connection file: ${CONNECTION_PATH}"
echo ""

# --- Phase 1: Quick validation ---
echo "=== Phase 1: Quick Validation ==="
echo ""
cd "${DEPLOYMENTS_DIR}"
uv run validate_deploy "${BOLT_URL}" neo4j "${PASSWORD}" Community

echo ""

# --- Phase 2: Full test suite ---
echo "=== Phase 2: Full Test Suite ==="
echo ""
cd "${SCRIPT_DIR}"
uv run test-ce --results "${CONNECTION_FILE}"
