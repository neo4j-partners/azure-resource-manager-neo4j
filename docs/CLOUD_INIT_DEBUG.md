# Cloud-Init Debugging Guide

This guide helps you debug Neo4j deployments using cloud-init (Phase 3.0+).

---

## Quick Diagnostics

### Step 1: Check Cloud-Init Status

SSH to the VM and check if cloud-init completed successfully:

```bash
# Check overall status
cloud-init status

# Get detailed status
cloud-init status --long

# Check if cloud-init is still running
cloud-init status --wait
```

**Expected output when successful:**
```
status: done
```

**If you see:**
- `status: running` - Cloud-init is still executing (wait a few minutes)
- `status: error` - Cloud-init encountered an error (check logs below)
- `status: disabled` - Cloud-init is not enabled (deployment issue)

### Step 2: View Cloud-Init Logs

```bash
# Primary output log (shows script execution)
sudo cat /var/log/cloud-init-output.log

# Detailed cloud-init log (shows module execution)
sudo cat /var/log/cloud-init.log

# Follow logs in real-time (if still running)
sudo tail -f /var/log/cloud-init-output.log
```

### Step 3: Check Neo4j Installation

```bash
# Check if Neo4j script executed
ls -la /tmp/neo4j-install.sh
cat /tmp/neo4j-install-complete

# Check Neo4j service status
sudo systemctl status neo4j

# View Neo4j logs
sudo journalctl -u neo4j -n 100 --no-pager

# Check Neo4j version
neo4j version
```

### Step 4: Verify Disk Mounting (Phase 3.1+)

```bash
# Check if data disk is mounted
df -h | grep neo4j

# Check mount details
mount | grep neo4j

# Check fstab entry
cat /etc/fstab | grep neo4j

# Test disk write
sudo touch /var/lib/neo4j/test-write
ls -la /var/lib/neo4j/test-write
sudo rm /var/lib/neo4j/test-write
```

---

## Common Issues and Solutions

### Issue: Cloud-Init Didn't Run

**Symptoms:**
- `cloud-init status` shows "not run" or "disabled"
- No cloud-init logs exist

**Causes:**
1. customData not passed correctly in Bicep template
2. Cloud-init not installed on VM image
3. VM image doesn't support cloud-init

**Solutions:**
```bash
# Check if cloud-init is installed
which cloud-init

# Check if customData was provided
sudo cat /var/lib/cloud/instance/user-data.txt | head -20

# Manually trigger cloud-init (for testing only)
sudo cloud-init init
sudo cloud-init modules --mode=config
sudo cloud-init modules --mode=final
```

### Issue: Script Execution Failed

**Symptoms:**
- Cloud-init status shows "done" but Neo4j not installed
- Errors in /var/log/cloud-init-output.log
- /tmp/neo4j-install-complete doesn't exist

**Common causes:**
1. **Bash script errors** - Check syntax in node.sh
2. **Missing permissions** - Script not executable
3. **Network issues** - Can't download Neo4j packages
4. **Disk space** - No space left on device

**Debug steps:**
```bash
# Check if script file exists and is executable
ls -la /tmp/neo4j-install.sh
file /tmp/neo4j-install.sh  # Should show "executable"

# Check script content (first few lines)
head -20 /tmp/neo4j-install.sh

# Try running script manually (see exact error)
sudo bash -x /tmp/neo4j-install.sh \
  "neo4j" \
  "test-password" \
  "unique123" \
  "eastus" \
  "5" \
  "No" \
  "None" \
  "No" \
  "None" \
  "1" \
  "-" \
  "/subscriptions/.../identity" \
  "resource-group-name" \
  "vmss-name" \
  "Enterprise"

# Check disk space
df -h

# Check network connectivity
ping -c 3 yum.neo4j.com
curl -I https://yum.neo4j.com/stable/5
```

### Issue: Neo4j Not Starting

**Symptoms:**
- Cloud-init completed successfully
- Script executed without errors
- Neo4j service fails to start

**Debug steps:**
```bash
# Check Neo4j service status
sudo systemctl status neo4j -l

# Check Neo4j logs for errors
sudo journalctl -u neo4j -n 200 --no-pager

# Check Neo4j configuration
sudo cat /etc/neo4j/neo4j.conf | grep -v "^#" | grep -v "^$"

# Check if Neo4j process is running
ps aux | grep neo4j

# Check if ports are available
sudo netstat -tulpn | grep -E "7474|7687"

# Try starting manually
sudo systemctl stop neo4j
sudo /usr/bin/neo4j console
```

### Issue: Cluster Not Forming

**Symptoms:**
- Individual nodes start successfully
- Cluster doesn't form or shows incorrect member count

**Debug steps:**
```bash
# Check cluster configuration
grep -E "dbms.cluster|server.discovery|server.cluster" /etc/neo4j/neo4j.conf

# Check DNS resolution of cluster members
ping -c 1 vm0
ping -c 1 vm1
ping -c 1 vm2

# Check cluster ports (5000, 6000, 7000)
sudo netstat -tulpn | grep -E "5000|6000|7000"

# Check cluster status via Neo4j
cypher-shell -u neo4j -p <password> "SHOW DATABASES"

# View cluster-related logs
sudo journalctl -u neo4j | grep -i cluster
```

### Issue: Parameters Not Substituted

**Symptoms:**
- Script contains literal `{{PLACEHOLDER}}` values
- Errors about undefined variables

**Causes:**
- Bicep replace() function not working correctly
- Placeholder names don't match

**Debug steps:**
```bash
# Check if placeholders remain in script
grep -o "{{[^}]*}}" /tmp/neo4j-install.sh

# If found, check cloud-init user data
sudo cat /var/lib/cloud/instance/user-data.txt | grep "{{"
```

**Solution:**
- Fix placeholder names in cloud-init YAML or Bicep template
- Ensure all placeholders are replaced before deployment

---

## Debugging Workflow

Use this systematic approach when diagnosing issues:

```
1. SSH to VM
   └─> ssh <admin-username>@<vm-public-ip>

2. Check cloud-init completed
   └─> cloud-init status
       ├─> If "running": wait and check again
       ├─> If "error": check logs (step 3)
       └─> If "done": verify Neo4j (step 4)

3. Check cloud-init logs
   └─> sudo cat /var/log/cloud-init-output.log
       └─> Look for errors or failures

4. Check Neo4j installation
   └─> ls /tmp/neo4j-install-complete
       ├─> If exists: Neo4j script completed
       └─> If missing: check script execution

5. Check Neo4j service
   └─> sudo systemctl status neo4j
       ├─> If active: Neo4j running correctly
       ├─> If failed: check Neo4j logs
       └─> If inactive: try starting manually

6. Check connectivity
   └─> curl http://localhost:7474
       └─> Should return Neo4j Browser HTML
```

---

## Useful Commands Reference

### Cloud-Init Commands

```bash
# Status and completion
cloud-init status
cloud-init status --long
cloud-init status --wait

# View configuration
sudo cat /var/lib/cloud/instance/user-data.txt

# Analyze logs
sudo cloud-init analyze show
sudo cloud-init analyze dump

# Clean and re-run (testing only - destroys data!)
sudo cloud-init clean
sudo cloud-init init
```

### Neo4j Commands

```bash
# Service management
sudo systemctl start neo4j
sudo systemctl stop neo4j
sudo systemctl restart neo4j
sudo systemctl status neo4j

# View logs
sudo journalctl -u neo4j -f
sudo journalctl -u neo4j --since "10 minutes ago"

# Check installation
neo4j version
neo4j status

# Connect to database
cypher-shell -u neo4j -p <password>
```

### System Commands

```bash
# Disk and filesystem
df -h
mount | grep neo4j
lsblk
sudo fdisk -l

# Network
ip addr show
ss -tulpn | grep neo4j
ping vm0  # Test DNS resolution

# Processes
ps aux | grep neo4j
pstree -p | grep neo4j

# Logs
sudo tail -f /var/log/messages
sudo dmesg | tail -50
```

---

## Phase-Specific Debugging

### Phase 3.0: Embedded Bash

**Key files:**
- `/tmp/neo4j-install.sh` - The embedded bash script
- `/tmp/neo4j-install-complete` - Completion marker

**What to check:**
- Script exists and is executable
- All parameters substituted correctly
- Script logic executes without errors

### Phase 3.1: Disk Operations (Future)

**Key files:**
- `/etc/fstab` - Persistent mount configuration

**What to check:**
- Disk partitioned correctly
- Filesystem created
- Mount point exists
- Disk mounted at /var/lib/neo4j

### Phase 3.2: Package Management (Future)

**Key files:**
- `/etc/yum.repos.d/neo4j.repo` - Neo4j repository configuration

**What to check:**
- Repository configured correctly
- Packages installed via yum
- Neo4j version correct

---

## Getting Help

If you can't resolve the issue:

1. **Collect diagnostic information:**
   ```bash
   # Save all relevant logs
   cloud-init status --long > cloud-init-status.txt
   sudo cat /var/log/cloud-init-output.log > cloud-init-output.log
   sudo journalctl -u neo4j -n 500 --no-pager > neo4j.log
   sudo cat /etc/neo4j/neo4j.conf > neo4j.conf
   ```

2. **Check for known issues** in GitHub repository

3. **Create detailed bug report** including:
   - Deployment parameters used
   - Cloud-init status and logs
   - Neo4j logs
   - Error messages
   - VM size and Azure region

---

## Tips for Faster Debugging

1. **Use multiple SSH sessions** - One for logs (`tail -f`), one for commands
2. **Check logs immediately** - Don't wait for full timeout
3. **Test DNS first** - Many cluster issues are DNS-related
4. **Verify disk before Neo4j** - Neo4j needs working disk
5. **Check one component at a time** - Isolate the failure point
6. **Compare working vs failing** - Deploy minimal test case

---

**Last Updated:** 2025-11-17 (Phase 3.0)
**Status:** Production Ready
