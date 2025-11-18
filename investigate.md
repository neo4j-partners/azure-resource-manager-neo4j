# Neo4j Enterprise Bicep Cluster Deployment Investigation

> Purpose: Systematic plan to find root cause of failing cluster deployment for the upgraded Bicep templates.
> Keep this document updated as you execute commands. Replace TODO markers with findings.

## 1. Immediate Context Capture
- Template used: `marketplace/neo4j-enterprise/mainTemplate.bicep` (commit: `TODO_COMMIT_HASH`)  
- Deployment scope: Resource Group (`TODO_RG_NAME`) in Subscription (`TODO_SUB_ID`)  
- Deployment name: `TODO_DEPLOYMENT_NAME`  
- Started at: `2025-11-17 00:00 UTC` (replace with actual)  
- Failure symptom (portal / CLI error message excerpt):  
```text
TODO paste error snippet
```  
- Neo4j version / expected topology: `TODO_VERSION`, cluster size `TODO_NODE_COUNT`  
- Expected resources (rough): LB, VMs/VMSS, NSGs, Managed disks, Public/Private IPs, Diagnostics storage, Script/Custom extensions.

### 1.a Test Harness Data (.arm-testing)
Source: `.arm-testing/config/settings.yaml`, `.arm-testing/config/scenarios.yaml`, latest cluster params file.
- Subscription: `47fd4ce5-a912-480e-bb81-95fbd59bb6c5` (name: Business Development)
- Default region: `westeurope`
- Scenario (cluster-v5): node_count=3, graph_database_version=5, vm_size=Standard_E4s_v5, disk_size=32, read_replica_count=0
- Latest inspected params file: `params-cluster-v5-20251117-204925.json`
  - nodeCount=3, readReplicaCount=0, vmSize=Standard_E4s_v5, readReplicaVmSize=Standard_E8s_v5, diskSize=32
  - location=westeurope, licenseType=Evaluation, GDS=No, Bloom=No
- Admin password present (redacted for security in investigation notes)

Recent cluster deployment attempts from `active-deployments.json`:
| Deployment Name | RG | Created UTC | Status |
|-----------------|----|-------------|--------|
| neo4j-deploy-cluster-v5-20251117-190816 | neo4j-test-cluster-v5-20251117-190816 | 02:08:19 | deleted |
| neo4j-deploy-cluster-v5-20251117-193829 | neo4j-test-cluster-v5-20251117-193829 | 02:38:32 | deleted |
| neo4j-deploy-cluster-v5-20251117-195005 | neo4j-test-cluster-v5-20251117-195005 | 02:50:06 | deleted |
| neo4j-deploy-cluster-v5-20251117-202206 | neo4j-test-cluster-v5-20251117-202206 | 03:22:08 | succeeded |
| neo4j-deploy-cluster-v5-20251117-203022 | neo4j-test-cluster-v5-20251117-203022 | 03:30:24 | succeeded |
| neo4j-deploy-cluster-v5-20251117-203947 | neo4j-test-cluster-v5-20251117-203947 | 03:39:49 | succeeded |
| neo4j-deploy-cluster-v5-20251117-204925 | neo4j-test-cluster-v5-20251117-204925 | 03:49:27 | succeeded |

Preliminary Observation: Early cluster attempts ended 'deleted' (likely failed/cleaned) followed by multiple successes—current failing case may be regression or new template change; confirm which deployment correlates to failure.

## 2. Hypotheses (Start Broad, Refine)
Check off / add as you eliminate.
- [ ] Template validation error (parameter mismatch / missing variable)
- [ ] Bicep compilation drift vs generated ARM (`mainTemplate-generated.json`) differences
- [ ] Azure deployment operation failed (extension provisioning timeout)
- [ ] Custom Script / cloud-init failed (Neo4j service not started)
- [ ] Networking: LB probe / NSG blocking internode ports
- [ ] VM/VMSS instance OS boot or disk mount issue
- [ ] Neo4j cluster formation timeout due to hostname/IP resolution
- [ ] Password / auth setup failed causing cluster join rejection
- [ ] Insufficient system resources (CPU, RAM, disk) or SKU mismatch
- [ ] Wrong ordering / dependency of resources in Bicep (dependsOn missing)

Add refined hypotheses as evidence appears.

## 3. Baseline Deployment Status
Commands (run in zsh). Set env first:
```zsh
SUB="<subscription-id>"
RG="<resource-group>"
DEPLOY_NAME="<deployment-name>"
```

### 3.1 Subscription & Context
```zsh
az account show -o table
az account set --subscription "$SUB"
az group show -n "$RG" -o jsonc
```
Record any anomalies: `TODO_NOTES`.

### 3.2 Deployment Result & Operations
```zsh
az deployment group show -g "$RG" -n "$DEPLOY_NAME" -o jsonc
az deployment operation group list -g "$RG" -n "$DEPLOY_NAME" -o json > deploy-operations.json
jq '.[].properties.provisioningState' deploy-operations.json | sort | uniq -c
jq -r '.[] | select(.properties.provisioningState=="Failed") | .properties.statusMessage' deploy-operations.json > failed-ops.txt
```
Capture failed operations summary in `failed-ops.txt`. Add key failing resource IDs below:
```
TODO_FAILED_RESOURCES
```

### 3.3 What-If (Dry Run) Against Current RG
(Validates drift or hidden conflicts.)
```zsh
az deployment group what-if -g "$RG" --template-file marketplace/neo4j-enterprise/mainTemplate.bicep --parameters @marketplace/neo4j-enterprise/parameters.json -o jsonc
```
Note discrepancies: `TODO_WHATIF_NOTES`.

## 4. Resource Enumeration & Health
### 4.1 List Core Resources
```zsh
az resource list -g "$RG" -o table
az resource list -g "$RG" --query "[?type=='Microsoft.Compute/virtualMachines']" -o table
az resource list -g "$RG" --query "[?type=='Microsoft.Network/networkInterfaces']" -o table
```

### 4.2 VM / VMSS Instance Health
If VM Scale Set used:
```zsh
VMSS_NAME="<vmss-name>" # if applicable
az vmss list-instances -g "$RG" -n "$VMSS_NAME" -o table
az vmss get-instance-view -g "$RG" -n "$VMSS_NAME" --instance-id 0 -o jsonc
```
If individual VMs:
```zsh
for VM in $(az vm list -g "$RG" --query '[].name' -o tsv); do
  echo "=== $VM ==="
  az vm get-instance-view -g "$RG" -n "$VM" --query instanceView.statuses -o table
  az vm extension list -g "$RG" --vm-name "$VM" -o table
done
```
Collect failed extensions (ProvisioningState != Succeeded): `TODO_VM_EXTENSION_ISSUES`.

### 4.3 Boot Diagnostics / Serial Console
```zsh
for VM in $(az vm list -g "$RG" --query '[].name' -o tsv); do
  az vm boot-diagnostics get-boot-log -g "$RG" -n "$VM" --output tsv > logs/${VM}-boot.log
  echo "Boot log saved: logs/${VM}-boot.log"
done
```
Scan for: failed mounts, cloud-init errors, Neo4j service errors.

### 4.4 Networking & Ports
Identify NICs and effective NSG/route:
```zsh
for NIC in $(az network nic list -g "$RG" --query '[].name' -o tsv); do
  az network nic show -g "$RG" -n "$NIC" --query "{name:name,privateIP:ipConfigurations[0].privateIpAddress,NSG:networkSecurityGroup.id}" -o jsonc
  az network nic show-effective-nsg -g "$RG" -n "$NIC" -o jsonc > nsg-effective-${NIC}.json
done
```
Load Balancer (if present):
```zsh
LB_NAME="<lb-name>"
az network lb show -g "$RG" -n "$LB_NAME" -o jsonc
az network lb probe list -g "$RG" --lb-name "$LB_NAME" -o table
```
Check required Neo4j cluster ports (default 5000, 6000, 7000, 7687, 7474 etc.) open internally.

### 4.5 DNS / Internal Name Resolution
If using internal hostnames:
```zsh
# From one VM to others
TARGET="<other-vm-private-ip-or-hostname>"
az vm run-command invoke -g "$RG" -n "$VM" --command-id RunShellScript --scripts "getent hosts $TARGET" "nc -zv $TARGET 7687" -o jsonc
```
Record failures: `TODO_CONNECTIVITY_NOTES`.

## 5. Deployment Scripts & Neo4j Service Validation
### 5.1 Custom Script / cloud-init Logs
Paths to inspect (typical): `/var/log/cloud-init.log`, `/var/log/cloud-init-output.log`, any script output under `/var/lib/waagent/`. Use run-command:
```zsh
az vm run-command invoke -g "$RG" -n "$VM" --command-id RunShellScript --scripts "sudo tail -n 200 /var/log/cloud-init-output.log" -o jsonc
```
Look for errors creating users, installing packages, configuring systemd.

### 5.2 Neo4j Service Status
```zsh
az vm run-command invoke -g "$RG" -n "$VM" --command-id RunShellScript --scripts "sudo systemctl status neo4j --no-pager" -o jsonc
az vm run-command invoke -g "$RG" -n "$VM" --command-id RunShellScript --scripts "sudo journalctl -u neo4j -n 200 --no-pager" -o jsonc
```
Capture anomalies: `TODO_NEO4J_STATUS`.

### 5.3 Cluster Membership & Logs
```zsh
az vm run-command invoke -g "$RG" -n "$VM" --command-id RunShellScript --scripts "sudo cypher-shell -u neo4j -p '<password>' 'CALL dbms.cluster.overview();'" -o jsonc
az vm run-command invoke -g "$RG" -n "$VM" --command-id RunShellScript --scripts "sudo grep -i 'cluster' /var/log/neo4j/debug.log | tail -n 100" -o jsonc
```
If cypher-shell fails: note error text in `TODO_CYPHER_ERRORS`.

## 6. Template / Bicep Analysis
### 6.1 Decompile & Diff
```zsh
bicep build marketplace/neo4j-enterprise/mainTemplate.bicep --outfile out.json
diff -u out.json marketplace/neo4j-enterprise/mainTemplate-generated.json > bicep-diff.patch || true
```
Investigate material differences (parameters, dependsOn). Notes: `TODO_BICEP_DIFF_NOTES`.

### 6.2 Parameters Validation
```zsh
jq '.' marketplace/neo4j-enterprise/parameters.json > /dev/null  # syntax check
# Optionally list required params from bicep
grep -R "param " marketplace/neo4j-enterprise/mainTemplate.bicep
```
Check any missing or incorrect values: `TODO_PARAM_ISSUES`.

### 6.3 DependsOn / Ordering
Search for critical resources (e.g., scripts extensions) ensuring they depend on underlying VM/VMSS creation.
```zsh
grep -n "dependsOn" marketplace/neo4j-enterprise/mainTemplate.bicep | head -n 50
```
Potential ordering issues: `TODO_DEPENDSON_NOTES`.

## 7. Azure Activity & Diagnostic Logs
```zsh
az monitor activity-log list --subscription "$SUB" --resource-group "$RG" --offset 4h -o jsonc > activity.json
jq -r '.[].status' activity.json | sort | uniq -c
```
Notable failures: `TODO_ACTIVITY_LOGS`.

If diagnostics workspace configured, query metrics for VM CPU/mem (optional).

## 8. Iterative Root Cause Narrowing
Use a table to summarize elimination:
| Hypothesis | Evidence | Status (Open/Closed) | Notes |
|------------|----------|----------------------|-------|
| Template param mismatch | TODO | Open |  |
| Extension failure | TODO | Open |  |
| Network port blocked | TODO | Open |  |
| Cluster join failure | TODO | Open |  |

Update as you proceed.

## 9. Next Remediation Paths (Choose Once Cause Found)
- Misconfiguration: Adjust parameters.json and redeploy incremental.
- Extension script failure: Fix script, apply `az vm extension set` or redeploy with `--mode Complete`.
- Networking: Update NSG rules / LB probes, then validate with netcat.
- Neo4j service config: Patch config files (`neo4j.conf`), restart service.
- Ordering: Add `dependsOn` in Bicep and re-run `az deployment group create`.

## 10. Redeployment Strategy
Dry run fix via what-if again. Then:
```zsh
az deployment group create -g "$RG" -n "${DEPLOY_NAME}-retry" --template-file marketplace/neo4j-enterprise/mainTemplate.bicep --parameters @marketplace/neo4j-enterprise/parameters.json -o jsonc
```
Track new operations diff vs previous failure.

## 11. Progress Log (Append Chronologically)
Use format:
```
[YYYY-MM-DD HH:MM] Step: <short description>
Result: <success/failure>
Action: <next move>
```
Entries:
```
[2025-11-17 12:00] Step: Initialized investigation file
Result: success
Action: Awaiting subscription/RG/deployment identifiers to populate context.
[2025-11-17 12:10] Step: Ingested test harness cluster data
Result: success
Action: Need exact failing deployment name to proceed with az operation scrape.
```

## 12. Summary (Fill After Resolution)
Root Cause: `TODO_ROOT_CAUSE`  
Fix Applied: `TODO_FIX`  
Verification Steps Done: `TODO_VERIFICATION`  
Remaining Risks: `TODO_RISKS`  

---
Checklist Quick View:
- [ ] Collect baseline deployment data
- [ ] Extract failed operations
- [ ] Enumerate VMs & extensions
- [ ] Gather boot diagnostics
- [ ] Validate networking & ports
- [ ] Inspect cloud-init / script logs
- [ ] Check Neo4j service health
- [ ] Query cluster status via cypher-shell
- [ ] Diff Bicep vs generated ARM
- [ ] Validate parameters
- [ ] Review dependsOn
- [ ] Activity log anomalies
- [ ] Narrow hypotheses table
- [ ] Implement remediation
- [ ] Confirm cluster stable
- [ ] Document root cause

Keep this file updated; do not delete TODO markers until resolved.
