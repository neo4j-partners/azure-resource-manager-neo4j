#!/bin/bash
set -euo pipefail

echo Running startup script...
export password=${1}

# --- Resilient package installation ------------------------------------------
# On Azure, RHEL PAYG images fetch base-OS packages from Microsoft-hosted RHUI
# (Red Hat Update Infrastructure). yum install refreshes ALL enabled repos, so a
# transient RHUI error fails the whole install even when the Neo4j repo is
# healthy. We have observed:
#   "Status code: 400 for https://rhui4-1.microsoft.com/.../repomd.xml"
# Retry with a cache refresh so a transient failure self-heals rather than
# failing the deployment. (If the failure is deterministic, the deploy still
# surfaces it after the retries are exhausted.)
retry() {
  local -r -i max_attempts=10
  local -i attempt=1
  local -i delay=15
  until "$@"; do
    if (( attempt >= max_attempts )); then
      echo "Command failed after ${max_attempts} attempts: $*" >&2
      return 1
    fi
    echo "Attempt ${attempt}/${max_attempts} failed for: $* - cleaning yum cache, retrying in ${delay}s..." >&2
    yum clean all || true
    sleep "${delay}"
    attempt+=1
  done
}

echo "Turning off firewalld"
systemctl stop firewalld
systemctl disable firewalld

echo "Installing Graph Database..."
rpm --import https://debian.neo4j.com/neotechnology.gpg.key
echo "[neo4j]
name=Neo4j RPM Repository
baseurl=https://yum.neo4j.com/stable/latest
enabled=1
gpgcheck=1" > /etc/yum.repos.d/neo4j.repo
# Readiness gate: refresh repo metadata first (installs nothing); retried because Azure RHUI can return transient errors on repomd.xml.
retry yum -y makecache
retry yum -y install neo4j

echo "Configuring network in neo4j.conf..."
sed -i "s/#server.default_listen_address=0.0.0.0/server.default_listen_address=0.0.0.0/g" /etc/neo4j/neo4j.conf

echo "Starting Neo4j..."
neo4j-admin dbms set-initial-password "$password"
systemctl enable neo4j
/usr/bin/neo4j start
