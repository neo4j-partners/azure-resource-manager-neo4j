# Template Improvements and Neo4j Best Practices Alignment

This document provides a comprehensive analysis of improvements and fixes for the Azure Neo4j deployment template, based on Neo4j operational documentation and industry best practices.

> **Note:** This template is deployed via the Azure Marketplace. Recommendations must balance security best practices with marketplace usability—customers expect a working deployment with minimal friction.

---

## Table of Contents

1. [Marketplace Deployment Considerations](#marketplace-deployment-considerations)
2. [Critical Security Improvements](#1-critical-security-improvements)
3. [Network Security Hardening](#2-network-security-hardening)
4. [Memory and Performance Configuration](#3-memory-and-performance-configuration)
5. [SSL/TLS Encryption](#4-ssltls-encryption)
6. [Backup and Recovery](#5-backup-and-recovery)
7. [Monitoring and Observability](#6-monitoring-and-observability)
8. [Cluster Configuration Improvements](#7-cluster-configuration-improvements)
9. [Cloud-Init Script Improvements](#8-cloud-init-script-improvements)
10. [Azure Infrastructure Improvements](#9-azure-infrastructure-improvements)
11. [Operational Best Practices](#10-operational-best-practices)
12. [Documentation and Usability](#11-documentation-and-usability)

---

## Marketplace Deployment Considerations

### Key Constraints

When deploying via Azure Marketplace, several factors affect implementation decisions:

1. **Unknown Customer Environment**: We don't know customer IP addresses, existing networks, or security requirements in advance
2. **Ease of Use**: Customers expect a working deployment without extensive configuration
3. **Self-Service**: No Neo4j support during initial deployment—errors must be recoverable
4. **Cost Sensitivity**: Optional features that add cost should be opt-in
5. **Enterprise Requirements**: Large customers need VNet injection, private connectivity, and compliance features

### Design Principles

| Principle | Approach |
|-----------|----------|
| Security by Default | Secure defaults with options to relax for testing |
| Progressive Disclosure | Basic config first, advanced options in separate sections |
| Graceful Degradation | Features should fail safely if misconfigured |
| Customer Control | Expose parameters for enterprise customization |

---

## 1. Critical Security Improvements

### 1.1 Disable HTTP in Favor of HTTPS

**Current Issue:** The template enables both HTTP (7474) and HTTPS (7473) access from the Internet.

**Neo4j Best Practice:** "If you're using certificates and SSL, you should strongly consider disabling HTTP access on port 7474 to your Neo4j instance. Why offer unencrypted traffic when you've configured secure encrypted traffic?"

**Recommendation:**
- Add a parameter to optionally disable HTTP (7474) when HTTPS is configured
- Default to HTTPS-only for production deployments
- Update `network.bicep` to conditionally exclude the HTTP rule

```bicep
// Add parameter
param enableHttpAccess bool = false

// Conditionally include HTTP rule only when explicitly enabled
```

### 1.2 SSH Access Restriction

**Current Issue:** SSH (port 22) is open to the entire Internet (`sourceAddressPrefix: 'Internet'`).

**Best Practice:** [Microsoft recommends](https://learn.microsoft.com/en-us/azure/security/fundamentals/iaas) disabling direct SSH access from the Internet and using JIT access or Azure Bastion.

#### Marketplace Challenge
We don't know customer IP addresses in advance, making static IP restriction difficult.

#### Solution Options (in order of Azure's preference)

**Option A: Add Customer-Configurable IP Parameter (Recommended for Marketplace)**

Add to `createUiDefinition.json`:
```json
{
  "name": "sshSourceAddressPrefix",
  "type": "Microsoft.Common.TextBox",
  "label": "Allowed SSH Source IP/CIDR",
  "defaultValue": "Internet",
  "toolTip": "IP address or CIDR range allowed for SSH. Enter 'Internet' for any source (not recommended for production) or your IP/range like '203.0.113.0/24'. Find your IP at whatismyip.com",
  "constraints": {
    "required": true,
    "regex": "^(Internet|[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}(/[0-9]{1,2})?)$",
    "validationMessage": "Enter 'Internet' or a valid IP address/CIDR range"
  }
},
{
  "name": "sshWarning",
  "type": "Microsoft.Common.InfoBox",
  "visible": "[equals(steps('networkConfig').sshSourceAddressPrefix, 'Internet')]",
  "options": {
    "icon": "Warning",
    "text": "Warning: SSH access from the entire Internet is not recommended for production. Consider restricting to your IP address or corporate network range."
  }
}
```

**Option B: Optional Azure Bastion (Enterprise Feature)**

Azure Bastion provides secure SSH/RDP without public IPs but adds ~$140/month cost.

Add as optional checkbox in `createUiDefinition.json`:
```json
{
  "name": "enableBastion",
  "type": "Microsoft.Common.CheckBox",
  "label": "Enable Azure Bastion for secure SSH access (adds ~$140/month)",
  "defaultValue": false,
  "toolTip": "Azure Bastion provides secure browser-based SSH without exposing VMs to the Internet"
}
```

When enabled, create Bastion resources in Bicep:
```bicep
// Bastion requires dedicated subnet with specific name
resource bastionSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-05-01' = if (enableBastion) {
  name: 'AzureBastionSubnet'
  parent: vnet
  properties: {
    addressPrefix: '10.0.255.0/26'  // Minimum /26 required
  }
}

resource bastionHost 'Microsoft.Network/bastionHosts@2023-05-01' = if (enableBastion) {
  name: 'bastion-neo4j-${resourceSuffix}'
  location: location
  sku: { name: 'Basic' }
  properties: {
    ipConfigurations: [{
      name: 'bastionIpConfig'
      properties: {
        subnet: { id: bastionSubnet.id }
        publicIPAddress: { id: bastionPublicIp.id }
      }
    }]
  }
}
```

**Option C: Just-in-Time (JIT) VM Access**

Document as post-deployment recommendation. Requires Microsoft Defender for Cloud (paid tier).

#### Recommended Implementation

1. Add `sshSourceAddressPrefix` parameter with `Internet` default
2. Show warning when `Internet` is selected
3. Document Azure Bastion and JIT as post-deployment hardening options
4. Consider Bastion as future optional feature for enterprise tier

### 1.3 SELinux Configuration

**Current Issue:** Cloud-init disables SELinux entirely (`setenforce 0` and sets to `permissive`).

**Best Practice:** SELinux should remain enforcing when possible, with proper Neo4j contexts configured.

#### Marketplace Decision: Keep Disabled

**Rationale:**
- Neo4j does not ship with SELinux policy modules
- Enabling SELinux would cause cryptic "permission denied" errors for customers
- This is common practice for database marketplace offerings (MongoDB, Elasticsearch, etc.)
- Enterprise customers can re-enable and configure custom policies post-deployment

**Recommendation:**
Keep SELinux disabled but document the decision in cloud-init:
```yaml
# SELinux set to permissive for Neo4j compatibility
# Neo4j does not provide SELinux policies, enabling would cause permission errors
# Enterprise customers requiring SELinux can configure custom policies post-deployment
# See: https://neo4j.com/docs/operations-manual/current/installation/linux/
- setenforce 0
- sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
```

### 1.4 Firewalld Configuration

**Current Issue:** Cloud-init completely disables firewalld.

**Best Practice:** Use firewalld with appropriate rules rather than disabling it entirely.

#### Marketplace Decision: Keep Disabled

**Rationale:**
- Azure NSGs provide network-level filtering (the appropriate layer for cloud)
- Host firewalls add complexity for customer troubleshooting
- Dual firewalls (NSG + host) create confusion when debugging connectivity
- Most Azure marketplace offerings (including Microsoft's own) disable host firewalls

**Recommendation:**
Keep firewalld disabled. The NSG rules in `network.bicep` are the proper mechanism for Azure network security. Document this in cloud-init:
```yaml
# Firewalld disabled - Azure NSG provides network filtering
# Host-level firewalls not needed when NSG rules are properly configured
# This follows Azure marketplace best practices for IaaS deployments
- systemctl stop firewalld
- systemctl disable firewalld
```

**Alternative (if host firewall is required by compliance):**
```yaml
# Enable firewalld with Neo4j ports (use only if NSG alone is insufficient)
runcmd:
  - firewall-cmd --permanent --add-port=7474/tcp   # HTTP
  - firewall-cmd --permanent --add-port=7473/tcp   # HTTPS
  - firewall-cmd --permanent --add-port=7687/tcp   # Bolt
  - firewall-cmd --permanent --add-port=7688/tcp   # Bolt routing
  - firewall-cmd --permanent --add-port=6000/tcp   # Cluster (internal only)
  - firewall-cmd --permanent --add-port=7000/tcp   # Raft (internal only)
  - firewall-cmd --reload
```

---

## 2. Network Security Hardening

### 2.1 NSG Rule Source Address Restrictions

**Current Issue:** Multiple ports open to `Internet` source:
- HTTP (7474)
- HTTPS (7473)
- Bolt (7687)
- Bolt Routing (7688)

#### Marketplace Approach

Similar to SSH, add customer-configurable source address restrictions:

```json
{
  "name": "neo4jSourceAddressPrefix",
  "type": "Microsoft.Common.TextBox",
  "label": "Allowed Client Source IP/CIDR",
  "defaultValue": "Internet",
  "toolTip": "IP address or CIDR range allowed to access Neo4j ports (7474, 7473, 7687). Use 'Internet' for public access or restrict to your network.",
  "constraints": {
    "required": true
  }
}
```

### 2.2 VNet Configuration and Injection

**Current Issue:**
- VNet uses very large address space (`10.0.0.0/8`) with subnet (`10.0.0.0/16`)
- Template only creates new VNets, no existing VNet support

#### Marketplace Enhancement: VNet Injection (High Priority)

Many enterprise customers require deploying into their existing VNet for:
- Integration with existing network topology
- Private connectivity (no public IPs)
- Compliance with network security policies
- Hub-spoke architecture compatibility

**Add to `createUiDefinition.json` - Network Configuration Step:**
```json
{
  "name": "networkConfig",
  "label": "Network Configuration",
  "subLabel": {
    "preValidation": "Configure networking",
    "postValidation": "Done"
  },
  "bladeTitle": "Network Settings",
  "elements": [
    {
      "name": "virtualNetwork",
      "type": "Microsoft.Network.VirtualNetworkCombo",
      "label": {
        "virtualNetwork": "Virtual Network",
        "subnets": "Subnet"
      },
      "toolTip": {
        "virtualNetwork": "Create a new virtual network or select an existing one",
        "subnets": "Subnet for Neo4j VMs. For existing VNets, select a subnet with sufficient IP addresses."
      },
      "defaultValue": {
        "name": "neo4j-vnet",
        "addressPrefixSize": "/16"
      },
      "constraints": {
        "minAddressPrefixSize": "/24"
      },
      "options": {
        "hideExisting": false
      },
      "subnets": {
        "neo4jSubnet": {
          "label": "Neo4j Subnet",
          "defaultValue": {
            "name": "neo4j-subnet",
            "addressPrefixSize": "/24"
          },
          "constraints": {
            "minAddressPrefixSize": "/28",
            "minAddressCount": 10,
            "requireContiguousAddresses": true
          }
        }
      },
      "visible": true
    },
    {
      "name": "publicIpOption",
      "type": "Microsoft.Common.OptionsGroup",
      "label": "Public IP Configuration",
      "defaultValue": "Assign public IPs",
      "toolTip": "Choose whether VMs should have public IP addresses",
      "constraints": {
        "allowedValues": [
          {
            "label": "Assign public IPs (required for Internet access)",
            "value": "public"
          },
          {
            "label": "Private only (requires VPN/ExpressRoute for access)",
            "value": "private"
          }
        ],
        "required": true
      }
    }
  ]
}
```

**Update `main.bicep` for VNet Injection:**
```bicep
@description('Use existing VNet (true) or create new (false)')
param useExistingVnet bool = false

@description('Existing VNet resource ID (required if useExistingVnet is true)')
param existingVnetId string = ''

@description('Existing subnet resource ID (required if useExistingVnet is true)')
param existingSubnetId string = ''

// Conditionally create or reference network
module network 'modules/network.bicep' = if (!useExistingVnet) {
  name: 'network-deployment'
  params: {
    location: location
    resourceSuffix: resourceSuffix
    vnetAddressPrefix: vnetAddressPrefix
    subnetAddressPrefix: subnetAddressPrefix
  }
}

var effectiveSubnetId = useExistingVnet ? existingSubnetId : network.outputs.subnetId
```

### 2.3 Private Deployment Support

**Current Issue:** No support for private-only deployments (no public IPs).

**Recommendation:**
Add option to deploy without public IPs. This requires:
- VNet injection (existing VNet with connectivity)
- No public IP on VMs
- Load balancer with private frontend IP only

```bicep
@description('Assign public IP addresses to VMs')
param assignPublicIps bool = true
```

When `assignPublicIps` is false:
- Remove `publicIPAddressConfiguration` from VMSS
- Configure internal load balancer instead of public
- Document that VPN/ExpressRoute is required for access

---

## 3. Memory and Performance Configuration

### 3.1 Explicit Memory Configuration

**Current Issue:** Template relies on `neo4j-admin server memory-recommendation` auto-configuration.

**Neo4j Best Practice:** "To have good control of the system behavior, it is recommended to always define the page cache and heap size parameters explicitly in neo4j.conf."

**Recommendation:**
- Add optional parameters for explicit memory configuration
- Provide VM-size-to-memory mapping recommendations
- Document memory sizing guidelines

```bicep
@description('Neo4j heap max size (e.g., "8g"). Empty means auto-configure.')
param heapMaxSize string = ''

@description('Neo4j page cache size (e.g., "12g"). Empty means auto-configure.')
param pageCacheSize string = ''
```

**Memory Sizing Guide (per Neo4j docs):**
| VM Size | RAM | Recommended Heap | Recommended Page Cache |
|---------|-----|------------------|----------------------|
| Standard_E4s_v5 | 32 GB | 8g | 16g |
| Standard_E8s_v5 | 64 GB | 16g | 35g |
| Standard_E16s_v5 | 128 GB | 31g | 70g |

### 3.2 Page Cache Warmup (Enterprise)

**Current Issue:** No page cache warmup configuration.

**Neo4j Best Practice:** "Active Warmup (Enterprise) enables pre-loading of hot data to reduce page-fault spikes on startup."

**Recommendation:**
Add to cloud-init configuration:
```yaml
- echo "db.memory.pagecache.warmup.enable=true" >> /etc/neo4j/neo4j.conf
- echo "db.memory.pagecache.warmup.preload=true" >> /etc/neo4j/neo4j.conf
```

### 3.3 Disk Configuration Improvements

**Current Issue:** Data disk uses `Premium_LRS` with `caching: 'None'`.

**Recommendation:**
- Add parameter for storage account type (Premium_LRS, Premium_ZRS, UltraSSD_LRS)
- Consider read caching for read-heavy workloads
- Add Ultra SSD support for high-performance requirements

```bicep
@allowed(['Premium_LRS', 'Premium_ZRS', 'UltraSSD_LRS'])
param diskStorageAccountType string = 'Premium_LRS'

@allowed(['None', 'ReadOnly', 'ReadWrite'])
param diskCaching string = 'None'
```

---

## 4. SSL/TLS Encryption

### 4.1 Built-in TLS Configuration

**Current Issue:** No SSL/TLS configuration in the template.

**Neo4j Best Practice:** "It is considered best practice to use certificates with reasonably short duration" and enable TLS for all connections.

#### Marketplace Challenge
TLS requires certificates, but we can't pre-provision certificates for unknown customer domains.

#### Certificate Options for Marketplace

| Option | Pros | Cons | Recommended For |
|--------|------|------|-----------------|
| **Self-Signed** | Zero config, works immediately | Browser warnings, not trusted | Development/testing |
| **Let's Encrypt** | Free, trusted, automated | Requires port 80, public DNS | Public deployments |
| **Customer-Provided** | Full control, enterprise certs | Requires customer action | Enterprise |
| **Azure Key Vault** | Centralized, secure | Complex setup | Advanced enterprise |

#### Recommended Implementation: Tiered Approach

**Add to `createUiDefinition.json`:**
```json
{
  "name": "tlsConfig",
  "label": "TLS/SSL Configuration",
  "elements": [
    {
      "name": "enableTls",
      "type": "Microsoft.Common.CheckBox",
      "label": "Enable TLS/SSL encryption for Neo4j connections",
      "defaultValue": false,
      "toolTip": "Enables encrypted HTTPS (7473) and Bolt+SSL (7687) connections"
    },
    {
      "name": "tlsCertificateSource",
      "type": "Microsoft.Common.OptionsGroup",
      "label": "Certificate Source",
      "visible": "[steps('tlsConfig').enableTls]",
      "defaultValue": "Self-signed (development only)",
      "constraints": {
        "allowedValues": [
          {
            "label": "Self-signed (development only)",
            "value": "selfSigned"
          },
          {
            "label": "Let's Encrypt (free, requires public DNS)",
            "value": "letsEncrypt"
          },
          {
            "label": "Provide my own certificate",
            "value": "custom"
          }
        ]
      }
    },
    {
      "name": "letsEncryptEmail",
      "type": "Microsoft.Common.TextBox",
      "label": "Let's Encrypt notification email",
      "visible": "[equals(steps('tlsConfig').tlsCertificateSource, 'letsEncrypt')]",
      "toolTip": "Email for certificate expiration notifications",
      "constraints": {
        "required": true,
        "regex": "^[\\w.-]+@[\\w.-]+\\.[a-zA-Z]{2,}$",
        "validationMessage": "Enter a valid email address"
      }
    },
    {
      "name": "customCertificate",
      "type": "Microsoft.Common.TextBox",
      "label": "TLS Certificate (Base64-encoded PEM)",
      "visible": "[equals(steps('tlsConfig').tlsCertificateSource, 'custom')]",
      "multiLine": true,
      "constraints": {
        "required": true
      }
    },
    {
      "name": "customPrivateKey",
      "type": "Microsoft.Common.PasswordBox",
      "label": {
        "password": "TLS Private Key (Base64-encoded PEM)",
        "confirmPassword": "Confirm Private Key"
      },
      "visible": "[equals(steps('tlsConfig').tlsCertificateSource, 'custom')]",
      "options": {
        "hideConfirmation": true
      }
    }
  ]
}
```

**Cloud-init TLS setup:**
```yaml
- |
  ENABLE_TLS="${enable_tls}"
  TLS_SOURCE="${tls_certificate_source}"

  if [ "$ENABLE_TLS" == "true" ]; then
    echo "=== Configuring TLS ==="

    # Create certificate directories
    mkdir -p /var/lib/neo4j/certificates/{bolt,https,cluster}/{trusted,revoked}
    chown -R neo4j:neo4j /var/lib/neo4j/certificates

    case "$TLS_SOURCE" in
      "selfSigned")
        # Generate self-signed certificate
        openssl req -x509 -newkey rsa:4096 -keyout /var/lib/neo4j/certificates/bolt/private.key \
          -out /var/lib/neo4j/certificates/bolt/public.crt -days 365 -nodes \
          -subj "/CN=${PUBLIC_HOSTNAME}"
        cp /var/lib/neo4j/certificates/bolt/* /var/lib/neo4j/certificates/https/
        echo "Self-signed certificate generated"
        ;;

      "letsEncrypt")
        # Install certbot and obtain certificate
        dnf install -y certbot
        certbot certonly --standalone --non-interactive --agree-tos \
          -m "${lets_encrypt_email}" -d "${PUBLIC_HOSTNAME}"
        # Link certificates
        ln -sf /etc/letsencrypt/live/${PUBLIC_HOSTNAME}/fullchain.pem /var/lib/neo4j/certificates/bolt/public.crt
        ln -sf /etc/letsencrypt/live/${PUBLIC_HOSTNAME}/privkey.pem /var/lib/neo4j/certificates/bolt/private.key
        cp -L /var/lib/neo4j/certificates/bolt/* /var/lib/neo4j/certificates/https/
        # Setup auto-renewal
        echo "0 0 * * * root certbot renew --quiet && systemctl reload neo4j" > /etc/cron.d/certbot-renew
        ;;

      "custom")
        # Decode and install customer-provided certificates
        echo "${custom_certificate}" | base64 -d > /var/lib/neo4j/certificates/bolt/public.crt
        echo "${custom_private_key}" | base64 -d > /var/lib/neo4j/certificates/bolt/private.key
        cp /var/lib/neo4j/certificates/bolt/* /var/lib/neo4j/certificates/https/
        ;;
    esac

    # Set permissions
    chmod 644 /var/lib/neo4j/certificates/*/public.crt
    chmod 600 /var/lib/neo4j/certificates/*/private.key
    chown -R neo4j:neo4j /var/lib/neo4j/certificates

    # Enable TLS in Neo4j configuration
    cat >> /etc/neo4j/neo4j.conf <<EOF
# TLS Configuration
dbms.ssl.policy.bolt.enabled=true
dbms.ssl.policy.bolt.base_directory=/var/lib/neo4j/certificates/bolt
dbms.ssl.policy.bolt.private_key=private.key
dbms.ssl.policy.bolt.public_certificate=public.crt
dbms.ssl.policy.bolt.tls_versions=TLSv1.2,TLSv1.3

dbms.ssl.policy.https.enabled=true
dbms.ssl.policy.https.base_directory=/var/lib/neo4j/certificates/https
dbms.ssl.policy.https.private_key=private.key
dbms.ssl.policy.https.public_certificate=public.crt
dbms.ssl.policy.https.tls_versions=TLSv1.2,TLSv1.3

server.https.enabled=true
EOF

    echo "TLS configuration complete"
  fi
```

### 4.2 Intra-Cluster Encryption

**Current Issue:** Cluster communication is unencrypted.

**Neo4j Best Practice:** "To configure a cluster to encrypt its intra-cluster communication, set `dbms.ssl.policy.cluster.enabled` to true."

#### Marketplace Approach

For clusters, auto-generate internal certificates during provisioning:
```yaml
- |
  if [ "$NODE_COUNT" -gt 1 ]; then
    # Generate cluster-internal certificate (self-signed is acceptable for internal traffic)
    openssl req -x509 -newkey rsa:4096 -keyout /var/lib/neo4j/certificates/cluster/private.key \
      -out /var/lib/neo4j/certificates/cluster/public.crt -days 365 -nodes \
      -subj "/CN=neo4j-cluster-${UNIQUE_STRING}"

    cat >> /etc/neo4j/neo4j.conf <<EOF
# Intra-cluster encryption
dbms.ssl.policy.cluster.enabled=true
dbms.ssl.policy.cluster.base_directory=/var/lib/neo4j/certificates/cluster
dbms.ssl.policy.cluster.private_key=private.key
dbms.ssl.policy.cluster.public_certificate=public.crt
dbms.ssl.policy.cluster.client_auth=REQUIRE
dbms.ssl.policy.cluster.tls_versions=TLSv1.2,TLSv1.3
EOF
  fi
```

### 4.3 TLS Version Configuration

**Best Practice:** Enforce TLS 1.2+ and disable older protocols.

This is handled automatically in the TLS setup above with:
```
dbms.ssl.policy.*.tls_versions=TLSv1.2,TLSv1.3
```

---

## 5. Backup and Recovery

### 5.1 Backup Configuration

**Current Issue:** No backup configuration or integration.

**Neo4j Best Practice:** "It is very important to store a recent backup of your databases, including the system database, in a safe location."

#### Marketplace Approach: Optional Backup with Customer-Configured Storage

Backup should be **optional** because:
- Adds cost (storage, Recovery Services vault)
- Some customers have existing backup solutions
- Dev/test deployments may not need it

#### Implementation: Add Backup Configuration Step

**Add to `createUiDefinition.json`:**
```json
{
  "name": "backupConfig",
  "label": "Backup Configuration",
  "subLabel": {
    "preValidation": "Configure backup settings",
    "postValidation": "Done"
  },
  "bladeTitle": "Backup Settings",
  "elements": [
    {
      "name": "enableBackup",
      "type": "Microsoft.Common.CheckBox",
      "label": "Enable automated database backups",
      "defaultValue": false,
      "toolTip": "Configures daily Neo4j database backups to Azure Blob Storage"
    },
    {
      "name": "backupType",
      "type": "Microsoft.Common.OptionsGroup",
      "label": "Backup Type",
      "visible": "[steps('backupConfig').enableBackup]",
      "defaultValue": "Neo4j database backup",
      "constraints": {
        "allowedValues": [
          {
            "label": "Neo4j database backup (recommended)",
            "value": "neo4j"
          },
          {
            "label": "Azure VM backup (full disk)",
            "value": "azureBackup"
          }
        ]
      },
      "toolTip": "Neo4j backup creates consistent database backups. Azure VM backup captures entire disks."
    },
    {
      "name": "backupStorageAccount",
      "type": "Microsoft.Storage.StorageAccountSelector",
      "label": "Backup Storage Account",
      "visible": "[and(steps('backupConfig').enableBackup, equals(steps('backupConfig').backupType, 'neo4j'))]",
      "toolTip": "Storage account for Neo4j database backups. Will be created if 'Create new' is selected.",
      "defaultValue": {
        "name": "[concat('neo4jbackup', take(uniqueString(subscription().subscriptionId), 8))]",
        "type": "Standard_LRS"
      },
      "constraints": {
        "allowedTypes": ["Standard_LRS", "Standard_GRS", "Standard_ZRS"]
      },
      "options": {
        "hideExisting": false
      }
    },
    {
      "name": "backupRetentionDays",
      "type": "Microsoft.Common.Slider",
      "label": "Backup Retention (days)",
      "visible": "[steps('backupConfig').enableBackup]",
      "min": 7,
      "max": 365,
      "defaultValue": 30,
      "showStepMarkers": false,
      "toolTip": "Number of days to retain backup files"
    },
    {
      "name": "backupSchedule",
      "type": "Microsoft.Common.DropDown",
      "label": "Backup Schedule",
      "visible": "[steps('backupConfig').enableBackup]",
      "defaultValue": "Daily at 2:00 AM UTC",
      "constraints": {
        "allowedValues": [
          { "label": "Daily at 2:00 AM UTC", "value": "0 2 * * *" },
          { "label": "Daily at 6:00 AM UTC", "value": "0 6 * * *" },
          { "label": "Every 6 hours", "value": "0 */6 * * *" },
          { "label": "Every 12 hours", "value": "0 */12 * * *" }
        ]
      }
    }
  ]
}
```

**Add Bicep parameters and resources:**
```bicep
@description('Enable automated Neo4j backups')
param enableBackup bool = false

@description('Backup storage account name')
param backupStorageAccountName string = ''

@description('Backup retention in days')
param backupRetentionDays int = 30

@description('Backup schedule (cron format)')
param backupSchedule string = '0 2 * * *'

// Create storage account for backups if enabled
resource backupStorageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = if (enableBackup && backupStorageAccountName != '') {
  name: backupStorageAccountName
  location: location
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
  }
}

resource blobContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = if (enableBackup) {
  name: '${backupStorageAccount.name}/default/neo4j-backups'
  properties: {
    publicAccess: 'None'
  }
}

// Grant managed identity access to storage account
resource storageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableBackup) {
  name: guid(backupStorageAccount.id, identity.outputs.identityPrincipalId, 'Storage Blob Data Contributor')
  scope: backupStorageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: identity.outputs.identityPrincipalId
    principalType: 'ServicePrincipal'
  }
}
```

**Cloud-init backup configuration:**
```yaml
write_files:
  - path: /opt/neo4j/backup.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      set -euo pipefail

      STORAGE_ACCOUNT="${backup_storage_account}"
      CONTAINER="neo4j-backups"
      RETENTION_DAYS=${backup_retention_days}
      BACKUP_DIR="/var/backups/neo4j"
      DATE=$(date +%Y%m%d_%H%M%S)
      HOSTNAME=$(hostname)

      echo "=== Starting Neo4j Backup at $(date) ==="

      # Create backup directory
      mkdir -p $BACKUP_DIR/$DATE

      # Run Neo4j backup (database must be running)
      neo4j-admin database backup neo4j --to-path=$BACKUP_DIR/$DATE --include-metadata=all

      # Also backup configuration
      cp /etc/neo4j/neo4j.conf $BACKUP_DIR/$DATE/

      # Compress backup
      tar -czf $BACKUP_DIR/neo4j-backup-$HOSTNAME-$DATE.tar.gz -C $BACKUP_DIR $DATE

      # Upload to Azure Blob Storage using managed identity
      az login --identity
      az storage blob upload \
        --account-name $STORAGE_ACCOUNT \
        --container-name $CONTAINER \
        --file $BACKUP_DIR/neo4j-backup-$HOSTNAME-$DATE.tar.gz \
        --name $HOSTNAME/neo4j-backup-$DATE.tar.gz \
        --auth-mode login

      # Cleanup local backup
      rm -rf $BACKUP_DIR/$DATE $BACKUP_DIR/neo4j-backup-$HOSTNAME-$DATE.tar.gz

      # Delete old backups from blob storage (retention policy)
      CUTOFF_DATE=$(date -d "-$RETENTION_DAYS days" +%Y%m%d)
      az storage blob list --account-name $STORAGE_ACCOUNT --container-name $CONTAINER \
        --prefix "$HOSTNAME/" --auth-mode login --query "[?properties.lastModified<'$CUTOFF_DATE'].name" -o tsv | \
        xargs -I {} az storage blob delete --account-name $STORAGE_ACCOUNT --container-name $CONTAINER --name {} --auth-mode login

      echo "=== Backup Complete at $(date) ==="

runcmd:
  # Configure backup if enabled
  - |
    if [ "${enable_backup}" == "true" ]; then
      # Install Azure CLI for backup uploads
      rpm --import https://packages.microsoft.com/keys/microsoft.asc
      dnf install -y azure-cli

      # Setup backup cron job
      echo "${backup_schedule} root /opt/neo4j/backup.sh >> /var/log/neo4j-backup.log 2>&1" > /etc/cron.d/neo4j-backup
      chmod 644 /etc/cron.d/neo4j-backup

      echo "Backup configured: ${backup_schedule}"
    fi
```

### 5.2 Azure VM Backup Alternative

For customers preferring Azure-native backup:

```bicep
// Azure Backup vault (if Azure VM backup selected)
resource recoveryServicesVault 'Microsoft.RecoveryServices/vaults@2023-04-01' = if (enableBackup && backupType == 'azureBackup') {
  name: 'rsv-neo4j-${resourceSuffix}'
  location: location
  sku: {
    name: 'RS0'
    tier: 'Standard'
  }
  properties: {}
}
```

### 5.3 Recovery Documentation

Include in deployment outputs:
```bicep
output BackupStorageAccount string = enableBackup ? backupStorageAccountName : 'Backup not enabled'
output RestoreInstructions string = enableBackup ? 'Download backup from storage account and run: neo4j-admin database restore neo4j --from-path=<backup-path>' : ''
```

### 5.4 Configuration Backup

**Neo4j Best Practice:** "The neo4j.conf file must be backed up separately from the databases."

The backup script above includes `neo4j.conf`. Additionally, if TLS is enabled:
```yaml
# Include TLS certificates in backup
if [ -d "/var/lib/neo4j/certificates" ]; then
  cp -r /var/lib/neo4j/certificates $BACKUP_DIR/$DATE/
fi
```

---

## 6. Monitoring and Observability

### 6.1 Prometheus Metrics Endpoint

**Current Issue:** No monitoring configuration.

**Neo4j Best Practice:** Enable Prometheus endpoint for production monitoring.

**Recommendation:**
Add to cloud-init:
```yaml
# Enable Prometheus metrics
- echo "server.metrics.prometheus.enabled=true" >> /etc/neo4j/neo4j.conf
- echo "server.metrics.prometheus.endpoint=0.0.0.0:2004" >> /etc/neo4j/neo4j.conf
```

Update NSG with metrics port (restricted to monitoring infrastructure):
```bicep
{
  name: 'PrometheusMetrics'
  properties: {
    description: 'Prometheus metrics endpoint'
    protocol: 'Tcp'
    sourcePortRange: '*'
    destinationPortRange: '2004'
    sourceAddressPrefix: 'VirtualNetwork'  // Restrict to internal
    destinationAddressPrefix: '*'
    access: 'Allow'
    priority: 107
    direction: 'Inbound'
  }
}
```

### 6.2 Azure Monitor Integration

**Recommendation:**
- Add Azure Monitor agent installation
- Configure custom metrics for Neo4j
- Set up Log Analytics workspace integration

```bicep
@description('Log Analytics workspace ID for Azure Monitor')
param logAnalyticsWorkspaceId string = ''
```

### 6.3 Health Check Endpoint

**Current Issue:** No dedicated health check configuration.

**Recommendation:**
- Configure health probe endpoint
- Add Azure Load Balancer health probes for Neo4j
- Document health check endpoints

### 6.4 Alerting Configuration

**Recommendation:**
Add pre-configured alerts for:
- Cluster membership changes
- Transaction failures
- Memory pressure (heap/page cache)
- Disk space utilization
- Bolt connection failures

---

## 7. Cluster Configuration Improvements

### 7.1 Minimum Initial Primaries

**Current Issue:** Sets `dbms.cluster.minimum_initial_system_primaries_count=${NODE_COUNT}`.

**Neo4j Best Practice:** "In a typical cluster deployment, it is best to start with three system primaries to ensure write availability."

**Recommendation:**
- For clusters > 3 nodes, consider keeping minimum at 3 for faster startup
- Document the tradeoff between consistency and availability

### 7.2 Server Groups and Load Balancing

**Current Issue:** No server group configuration for intelligent routing.

**Neo4j Best Practice:** Configure server policies for load balancing.

**Recommendation:**
```yaml
# Add server groups for routing policies
- echo "server.groups=az1" >> /etc/neo4j/neo4j.conf
- echo "dbms.routing.load_balancing.plugin=server_policies" >> /etc/neo4j/neo4j.conf
```

### 7.3 Read Replica Support

**Current Issue:** Read replica configuration exists but is incomplete.

**Recommendation:**
- Complete read replica support for Neo4j 5.x
- Add parameters for secondary node count
- Configure separate scaling for read replicas

```bicep
@description('Number of secondary (read replica) nodes')
@minValue(0)
@maxValue(10)
param secondaryNodeCount int = 0
```

### 7.4 Availability Zones

**Current Issue:** No availability zone configuration.

**Azure Best Practice:** Distribute cluster nodes across availability zones.

**Recommendation:**
```bicep
@description('Deploy across availability zones')
param useAvailabilityZones bool = true
```

---

## 8. Cloud-Init Script Improvements

### 8.1 Error Handling and Logging

**Current Issue:** Limited error handling and logging in cloud-init scripts.

**Recommendation:**
```yaml
runcmd:
  - set -euo pipefail  # Exit on errors
  - exec > >(tee -a /var/log/neo4j-cloud-init.log) 2>&1
  - echo "Starting Neo4j provisioning at $(date)"
```

### 8.2 Retry Logic for Package Installation

**Current Issue:** No retry logic for network-dependent operations.

**Recommendation:**
```yaml
# Retry package installation
- |
  for i in {1..5}; do
    dnf install -y neo4j-enterprise && break
    echo "Retry $i: Package installation failed, waiting..."
    sleep 30
  done
```

### 8.3 Instance Metadata API Version

**Current Issue:** Uses old metadata API version (`api-version=2017-03-01`).

**Recommendation:**
Update to current stable version:
```yaml
- INSTANCE_METADATA=$(curl -H Metadata:true "http://169.254.169.254/metadata/instance/compute?api-version=2021-02-01")
```

### 8.4 Disk Wait Logic

**Current Issue:** Disk might not be immediately available.

**Recommendation:**
```yaml
# Wait for data disk to be available
- |
  while [ ! -e /dev/disk/azure/scsi1/lun0 ]; do
    echo "Waiting for data disk..."
    sleep 5
  done
```

### 8.5 Neo4j Startup Verification

**Current Issue:** Basic HTTP check only.

**Recommendation:**
Add more comprehensive readiness check:
```yaml
- |
  MAX_WAIT=300
  ELAPSED=0
  while [ $ELAPSED -lt $MAX_WAIT ]; do
    if curl -s http://localhost:7474 | grep -q "neo4j"; then
      echo "Neo4j is ready!"
      break
    fi
    echo "Waiting for Neo4j... ($ELAPSED seconds)"
    sleep 5
    ELAPSED=$((ELAPSED + 5))
  done
  if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo "ERROR: Neo4j failed to start within $MAX_WAIT seconds"
    exit 1
  fi
```

---

## 9. Azure Infrastructure Improvements

### 9.1 Customer-Managed Keys (CMK)

**Current Issue:** Uses platform-managed encryption keys.

**Best Practice:** Production deployments should consider CMK.

**Recommendation:**
```bicep
@description('Key Vault key URL for disk encryption')
param diskEncryptionKeyUrl string = ''

@description('Key Vault ID for disk encryption')
param keyVaultId string = ''
```

### 9.2 Accelerated Networking

**Current Issue:** Accelerated networking not explicitly enabled.

**Recommendation:**
```bicep
networkInterfaceConfigurations: [
  {
    name: 'nic'
    properties: {
      primary: true
      enableAcceleratedNetworking: true  // Add this
      // ...
    }
  }
]
```

### 9.3 Proximity Placement Groups

**Current Issue:** No proximity placement for low-latency cluster communication.

**Recommendation:**
```bicep
@description('Enable proximity placement group for cluster nodes')
param useProximityPlacementGroup bool = true

resource proximityPlacementGroup 'Microsoft.Compute/proximityPlacementGroups@2024-03-01' = if (useProximityPlacementGroup && nodeCount >= 3) {
  name: 'ppg-neo4j-${resourceSuffix}'
  location: location
}
```

### 9.4 Managed Disk Bursting

**Current Issue:** No disk bursting configuration.

**Recommendation:**
For Premium SSD v2 or larger disks, enable bursting:
```bicep
param enableDiskBursting bool = true
```

### 9.5 Tags Enhancement

**Current Issue:** Basic tagging only.

**Recommendation:**
Add comprehensive tags for cost management and governance:
```bicep
var commonTags = {
  Neo4jVersion: graphDatabaseVersion
  Neo4jEdition: licenseType
  NodeCount: string(nodeCount)
  DeployedBy: 'arm-template'
  TemplateVersion: '1.0.0'
  Environment: environment  // Add parameter
  CostCenter: costCenter    // Add parameter
  Owner: ownerEmail         // Add parameter
}
```

---

## 10. Operational Best Practices

### 10.1 Graceful Shutdown Configuration

**Current Issue:** No graceful shutdown handling.

**Recommendation:**
Configure systemd for graceful Neo4j shutdown:
```yaml
- mkdir -p /etc/systemd/system/neo4j.service.d
- |
  cat > /etc/systemd/system/neo4j.service.d/timeout.conf <<EOF
  [Service]
  TimeoutStopSec=120
  EOF
```

### 10.2 Log Rotation

**Current Issue:** No log rotation configuration.

**Recommendation:**
```yaml
write_files:
  - path: /etc/logrotate.d/neo4j
    content: |
      /var/log/neo4j/*.log {
        daily
        missingok
        rotate 14
        compress
        delaycompress
        notifempty
        copytruncate
      }
```

### 10.3 Automatic Security Updates

**Current Issue:** No automatic security update configuration.

**Recommendation:**
```yaml
packages:
  - yum-cron

runcmd:
  - systemctl enable yum-cron
  - systemctl start yum-cron
```

### 10.4 Transaction Log Configuration

**Current Issue:** Default transaction log settings.

**Neo4j Best Practice:** Configure transaction logs for production.

**Recommendation:**
```yaml
# Transaction log configuration
- echo "db.tx_log.rotation.retention_policy=2 days" >> /etc/neo4j/neo4j.conf
- echo "db.tx_log.rotation.size=256M" >> /etc/neo4j/neo4j.conf
```

### 10.5 Query Logging

**Current Issue:** No query logging configuration.

**Recommendation for debugging/audit:**
```yaml
# Query logging (enable for debugging)
- echo "db.logs.query.enabled=INFO" >> /etc/neo4j/neo4j.conf
- echo "db.logs.query.threshold=1s" >> /etc/neo4j/neo4j.conf
```

---

## 11. Documentation and Usability

### 11.1 Parameter Documentation

**Recommendation:**
- Add detailed descriptions to all parameters
- Include valid ranges and defaults
- Document interdependencies

### 11.2 Post-Deployment Runbook

**Recommendation:**
Create documentation for:
- First-time connection and password change
- Cluster status verification commands
- Common troubleshooting steps
- Scaling procedures

### 11.3 Cost Estimation

**Recommendation:**
Add documentation or tooling for:
- VM size cost comparison
- Storage cost estimation
- Network egress considerations

### 11.4 Version Support Matrix

**Recommendation:**
Document supported combinations:
| Neo4j Version | VM Image | APOC Version | Tested |
|---------------|----------|--------------|--------|
| 5.x | byol | Bundled | Yes |

### 11.5 Upgrade Path Documentation

**Recommendation:**
Document:
- Rolling upgrade procedures for clusters
- Version compatibility requirements
- Pre-upgrade checklist

---

## Implementation Priority

### Phase 1: High Priority (Security & Enterprise Readiness)

| Feature | Effort | Customer Impact | Section |
|---------|--------|-----------------|---------|
| **VNet Injection** | Medium | High - Enterprise requirement | 2.2 |
| **SSH IP Restriction** | Low | High - Security baseline | 1.2 |
| **TLS/SSL Options** | Medium | High - Production readiness | 4.1 |
| **Optional Backup** | Medium | High - Data protection | 5.1 |
| **Error handling in cloud-init** | Low | High - Reliability | 8.1 |

### Phase 2: Medium Priority (Performance & Operations)

| Feature | Effort | Customer Impact | Section |
|---------|--------|-----------------|---------|
| Page cache warmup | Low | Medium - Faster startup | 3.2 |
| Prometheus monitoring endpoint | Low | Medium - Observability | 6.1 |
| Availability zones | Medium | Medium - HA for enterprise | 7.4 |
| Accelerated networking | Low | Medium - Performance | 9.2 |
| Private deployment (no public IP) | Medium | Medium - Security-conscious customers | 2.3 |

### Phase 3: Lower Priority (Enhancements)

| Feature | Effort | Customer Impact | Section |
|---------|--------|-----------------|---------|
| Azure Bastion option | High | Low - Enterprise nice-to-have | 1.2 |
| HTTP disabling option | Low | Low - Already have HTTPS | 1.1 |
| Customer-managed keys | High | Low - Enterprise compliance | 9.1 |
| Enhanced tagging | Low | Low - Cost management | 9.5 |
| Query logging | Low | Low - Debugging aid | 10.5 |

### Marketplace UI Additions Summary

New `createUiDefinition.json` steps required:

1. **Network Configuration** (Phase 1)
   - VNet selector (new/existing)
   - Subnet configuration
   - Public IP option
   - SSH source restriction

2. **Security Configuration** (Phase 1)
   - TLS enable checkbox
   - Certificate source selector
   - Let's Encrypt email (conditional)
   - Custom certificate fields (conditional)

3. **Backup Configuration** (Phase 1)
   - Enable backup checkbox
   - Backup type selector
   - Storage account selector
   - Retention slider
   - Schedule dropdown

### Decision Log: Marketplace Tradeoffs

| Decision | Chosen Approach | Rationale |
|----------|-----------------|-----------|
| SELinux | Keep disabled | No Neo4j policies, would break deployment |
| Firewalld | Keep disabled | NSG is sufficient for Azure, simpler for customers |
| SSH default | Allow from Internet with warning | Can't know customer IPs, show warning |
| TLS default | Disabled (opt-in) | Requires config, self-signed causes confusion |
| Backup default | Disabled (opt-in) | Adds cost, not all deployments need it |
| VNet default | Create new | Simpler, existing VNet is opt-in |

---

## References

### Neo4j Official Documentation
- [Neo4j Operations Manual](https://neo4j.com/docs/operations-manual/current/)
- [Performance Tuning](https://neo4j.com/docs/operations-manual/current/performance/)
- [Memory Configuration](https://neo4j.com/docs/operations-manual/current/performance/memory-configuration/)
- [Clustering Architecture](https://neo4j.com/docs/operations-manual/current/clustering/introduction/)
- [Backup and Restore](https://neo4j.com/docs/operations-manual/current/backup-restore/)
- [SSL Framework](https://neo4j.com/docs/operations-manual/current/security/ssl-framework/)
- [Metrics and Monitoring](https://neo4j.com/docs/operations-manual/current/monitoring/metrics/)
- [Neo4j on Azure](https://neo4j.com/docs/operations-manual/current/cloud-deployments/neo4j-azure/)

### Neo4j Knowledge Base
- [Monitoring with Prometheus](https://neo4j.com/developer/kb/how-to-monitor-neo4j-with-prometheus/)
- [Memory Configuration Estimation](https://neo4j.com/developer/kb/how-to-estimate-initial-memory-configuration/)
- [Cardinality Tuning](https://neo4j.com/developer/kb/understanding-cypher-cardinality/)

### Azure Best Practices
- [Azure Security Best Practices](https://learn.microsoft.com/en-us/azure/security/fundamentals/best-practices-and-patterns)
- [Security Best Practices for IaaS Workloads](https://learn.microsoft.com/en-us/azure/security/fundamentals/iaas) - SSH/RDP restrictions, JIT access
- [Network Security Best Practices](https://learn.microsoft.com/en-us/azure/security/fundamentals/network-best-practices)
- [VM Scale Set Best Practices](https://learn.microsoft.com/en-us/azure/virtual-machine-scale-sets/virtual-machine-scale-sets-design-overview)
- [Azure Bastion ARM Template](https://learn.microsoft.com/en-us/azure/bastion/quickstart-host-arm-template)
- [Azure VM Backup with ARM Template](https://learn.microsoft.com/en-us/azure/backup/quick-backup-vm-template)

### Azure Marketplace
- [CreateUIDefinition Reference](https://learn.microsoft.com/en-us/azure/azure-resource-manager/managed-applications/create-uidefinition-overview)
- [VirtualNetworkCombo Control](https://learn.microsoft.com/en-us/azure/azure-resource-manager/managed-applications/microsoft-network-virtualnetworkcombo)
- [StorageAccountSelector Control](https://learn.microsoft.com/en-us/azure/azure-resource-manager/managed-applications/microsoft-storage-storageaccountselector)

### SSL/TLS Automation
- [Let's Encrypt with Azure VMs](https://learn.microsoft.com/en-us/azure/virtual-machines/linux/tutorial-secure-web-server)
- [Automating SSL with Azure and Let's Encrypt](https://medium.com/@brentrobinson5/automating-certificate-management-with-azure-and-lets-encrypt-fee6729e2b78)

### Community Resources
- [Neo4j Prometheus Grafana Monitoring](https://github.com/graphaware/monitoring-neo4j-prometheus-grafana)
- [Grafana Neo4j Dashboard](https://grafana.com/grafana/dashboards/10371-neo4j-dashboard/)
- [Elasticsearch Azure Marketplace](https://github.com/elastic/azure-marketplace) - Reference marketplace implementation
