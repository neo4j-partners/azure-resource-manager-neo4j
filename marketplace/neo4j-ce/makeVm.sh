#!/bin/bash
set -euo pipefail

# Create a generalized RHEL 9 image in Azure Compute Gallery for the neo4j-ce-vm marketplace offer
# Usage: ./makeVm.sh [resource-group] [region]
#
# Prerequisites:
#   - Azure CLI logged in with sufficient permissions
#
# This script:
#   1. Creates a resource group
#   2. Creates a VM from the approved RHEL 9 Gen2 base image
#   3. SSHs in to install latest updates and deprovision
#   4. Deallocates and generalizes the VM
#   5. Creates an Azure Compute Gallery and image definition
#   6. Captures the VM as an image version in the gallery
#   7. Grants Partner Center access to the gallery
#
# References:
#   https://learn.microsoft.com/en-us/partner-center/marketplace-offers/azure-vm-use-approved-base
#   https://learn.microsoft.com/en-us/azure/virtual-machines/generalize

RESOURCE_GROUP="${1:-neo4j-ce-image-rg}"
REGION="${2:-eastus2}"

VM_NAME="neo4j-ce-image-vm"
VM_SIZE="Standard_D2s_v5"
GALLERY_NAME="neo4jmarketplace"
IMAGE_DEFINITION="neo4j-ce-vm"
IMAGE_VERSION="1.0.0"

echo "=== Creating Neo4j CE VM Image ==="
echo "Resource Group:    ${RESOURCE_GROUP}"
echo "Region:            ${REGION}"
echo "VM Size:           ${VM_SIZE}"
echo "Gallery:           ${GALLERY_NAME}"
echo "Image Definition:  ${IMAGE_DEFINITION}"
echo "Image Version:     ${IMAGE_VERSION}"
echo ""

# --- Step 1: Ensure resource group exists ---
echo "[1/7] Checking resource group..."
if az group show --name "${RESOURCE_GROUP}" --output none 2>/dev/null; then
  echo "  Resource group '${RESOURCE_GROUP}' already exists."
else
  echo "  Creating resource group '${RESOURCE_GROUP}'..."
  az group create \
    --name "${RESOURCE_GROUP}" \
    --location "${REGION}" \
    --output none
fi

# --- Step 2: Create VM from approved RHEL 9 base image ---
echo "[2/7] Creating VM from RHEL 9 Gen2 base image..."

# Clean up existing VM from a previous failed run
if az vm show --resource-group "${RESOURCE_GROUP}" --name "${VM_NAME}" --output none 2>/dev/null; then
  echo "  Deleting existing VM '${VM_NAME}' from previous run..."
  az vm delete \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${VM_NAME}" \
    --force-deletion yes \
    --yes \
    --output none
fi

az vm create \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${VM_NAME}" \
  --image "RedHat:RHEL:9-lvm-gen2:latest" \
  --size "${VM_SIZE}" \
  --admin-username azureuser \
  --generate-ssh-keys \
  --public-ip-sku Standard \
  --output none

echo "VM created. Waiting for VM to be ready..."
az vm wait --resource-group "${RESOURCE_GROUP}" --name "${VM_NAME}" --created

# --- Step 3: Update, clean, and deprovision via SSH ---
echo "[3/7] Connecting to VM to update and deprovision..."
VM_IP=$(az vm show \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${VM_NAME}" \
  --show-details \
  --query publicIps \
  --output tsv)

echo "VM IP: ${VM_IP}"

# Wait for SSH to be ready
echo "Waiting for SSH to be available..."
for i in $(seq 1 30); do
  if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes "azureuser@${VM_IP}" "echo ready" 2>/dev/null; then
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "ERROR: SSH not available after 30 attempts"
    exit 1
  fi
  echo "  Attempt $i/30..."
  sleep 10
done

# Install latest updates (required for marketplace certification)
echo "Installing latest OS updates..."
ssh -o StrictHostKeyChecking=no "azureuser@${VM_IP}" \
  "sudo dnf update -y"

# Full deprovisioning sequence per Microsoft best practices:
# https://learn.microsoft.com/en-us/azure/virtual-machines/linux/create-upload-generic
echo "Deprovisioning VM..."
ssh -o StrictHostKeyChecking=no "azureuser@${VM_IP}" \
  "sudo rm -f /var/log/waagent.log && \
   sudo cloud-init clean --logs --seed && \
   sudo waagent -deprovision+user -force && \
   sudo rm -f ~/.bash_history && \
   export HISTSIZE=0" || true

echo "Waiting for deprovision to complete..."
sleep 10

# --- Step 4: Deallocate and generalize ---
echo "[4/7] Deallocating and generalizing VM..."
az vm deallocate \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${VM_NAME}"
az vm generalize \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${VM_NAME}"

# --- Step 5: Ensure Azure Compute Gallery and image definition exist ---
echo "[5/7] Checking Azure Compute Gallery..."
if az sig show --resource-group "${RESOURCE_GROUP}" --gallery-name "${GALLERY_NAME}" --output none 2>/dev/null; then
  echo "  Gallery '${GALLERY_NAME}' already exists."
else
  echo "  Creating gallery '${GALLERY_NAME}'..."
  az sig create \
    --resource-group "${RESOURCE_GROUP}" \
    --gallery-name "${GALLERY_NAME}" \
    --output none
fi

if az sig image-definition show --resource-group "${RESOURCE_GROUP}" --gallery-name "${GALLERY_NAME}" --gallery-image-definition "${IMAGE_DEFINITION}" --output none 2>/dev/null; then
  echo "  Image definition '${IMAGE_DEFINITION}' already exists."
else
  echo "  Creating image definition '${IMAGE_DEFINITION}'..."
  az sig image-definition create \
    --resource-group "${RESOURCE_GROUP}" \
    --gallery-name "${GALLERY_NAME}" \
    --gallery-image-definition "${IMAGE_DEFINITION}" \
    --publisher "neo4j" \
    --offer "neo4j-ce-vm" \
    --sku "per-core-hour" \
    --os-type Linux \
    --os-state Generalized \
    --hyper-v-generation V2 \
    --features "SecurityType=TrustedLaunch" \
    --output none
fi

# --- Step 6: Capture VM as image version ---
echo "[6/7] Capturing VM as image version ${IMAGE_VERSION} (this may take several minutes)..."

# Delete existing image version from a previous run
if az sig image-version show --resource-group "${RESOURCE_GROUP}" --gallery-name "${GALLERY_NAME}" --gallery-image-definition "${IMAGE_DEFINITION}" --gallery-image-version "${IMAGE_VERSION}" --output none 2>/dev/null; then
  echo "  Deleting existing image version ${IMAGE_VERSION} from previous run..."
  az sig image-version delete \
    --resource-group "${RESOURCE_GROUP}" \
    --gallery-name "${GALLERY_NAME}" \
    --gallery-image-definition "${IMAGE_DEFINITION}" \
    --gallery-image-version "${IMAGE_VERSION}" \
    --output none
fi

VM_ID=$(az vm show \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${VM_NAME}" \
  --query id \
  --output tsv)

az sig image-version create \
  --resource-group "${RESOURCE_GROUP}" \
  --gallery-name "${GALLERY_NAME}" \
  --gallery-image-definition "${IMAGE_DEFINITION}" \
  --gallery-image-version "${IMAGE_VERSION}" \
  --virtual-machine "${VM_ID}" \
  --output none

echo "Image version created."

# --- Step 7: Grant Partner Center access to gallery ---
echo "[7/7] Granting Partner Center access to gallery..."

# Register the Partner Center resource provider
az provider register --namespace Microsoft.PartnerCenterIngestion --wait --output none 2>/dev/null || true

GALLERY_ID=$(az sig show \
  --resource-group "${RESOURCE_GROUP}" \
  --gallery-name "${GALLERY_NAME}" \
  --query id \
  --output tsv)

# Compute Gallery Image Reader role
ROLE_ID="cf7c76d2-98a3-4358-a134-615aa78bf44d"

# Grant access to "Microsoft Partner Center Resource Provider"
PC_SP=$(az ad sp list --display-name "Microsoft Partner Center Resource Provider" --query '[0].id' --output tsv 2>/dev/null || true)
if [ -n "${PC_SP}" ]; then
  az role assignment create \
    --assignee-object-id "${PC_SP}" \
    --assignee-principal-type ServicePrincipal \
    --role "${ROLE_ID}" \
    --scope "${GALLERY_ID}" \
    --output none 2>/dev/null || true
  echo "  Granted access to Microsoft Partner Center Resource Provider"
else
  echo "  WARNING: 'Microsoft Partner Center Resource Provider' service principal not found."
  echo "  You may need to grant access manually in the Azure portal."
fi

# Grant access to "Compute Image Registry"
CIR_SP=$(az ad sp list --display-name "Compute Image Registry" --query '[0].id' --output tsv 2>/dev/null || true)
if [ -n "${CIR_SP}" ]; then
  az role assignment create \
    --assignee-object-id "${CIR_SP}" \
    --assignee-principal-type ServicePrincipal \
    --role "${ROLE_ID}" \
    --scope "${GALLERY_ID}" \
    --output none 2>/dev/null || true
  echo "  Granted access to Compute Image Registry"
else
  echo "  WARNING: 'Compute Image Registry' service principal not found."
  echo "  You may need to grant access manually in the Azure portal."
fi

echo ""
echo "=== VM Image Created Successfully ==="
echo ""
echo "Azure Compute Gallery: ${GALLERY_NAME}"
echo "Image Definition:      ${IMAGE_DEFINITION}"
echo "Image Version:         ${IMAGE_VERSION}"
echo "Gallery Resource ID:   ${GALLERY_ID}"
echo ""
echo "Next steps:"
echo "  1. Go to Partner Center > neo4j-ce-vm > per-core-hour > Technical Configuration"
echo "  2. Add VM Image with version ${IMAGE_VERSION}"
echo "  3. Select x64 Gen 2"
echo "  4. Under 'Azure Compute Gallery', select gallery '${GALLERY_NAME}'"
echo "     Image: '${IMAGE_DEFINITION}', Version: '${IMAGE_VERSION}'"
echo ""
echo "To clean up temporary resources (after publishing):"
echo "  az group delete --name ${RESOURCE_GROUP} --yes --no-wait"
