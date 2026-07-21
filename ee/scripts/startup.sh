#!/bin/bash
set -euo pipefail

echo Running startup script...
export password=${1}
export uniqueString=${2}
export location=${3}
export nodeCount=${4}

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

# Read-only diagnostics for the Azure RHUI base-OS repos. Gathers information
# only -- it changes nothing and can never fail the deployment (all output goes
# to stderr and the function always returns 0). Run before the install to record
# a healthy baseline, and on failure to capture exactly what works vs. what does
# not -- useful because the CustomScript extension runs in a different context
# than an interactive SSH session.
rhui_diagnostics() {
  local phase="${1:-diagnostics}"
  {
    echo "==================== RHUI diagnostics (${phase}) ===================="
    ( set +e
      echo "--- context (user / cwd / time) ---"; id; echo "PWD=${PWD}"; date
      echo "--- proxy & relevant env ---";         env | grep -Ei 'proxy|^path=|lang' | sort
      echo "--- cloud-init status ---";            cloud-init status 2>/dev/null
      echo "--- RHUI repo definitions ---";        cat /etc/yum.repos.d/rhui-*.repo 2>/dev/null
      echo "--- dnf / yum repo URL variables ---"; head -n 50 /etc/dnf/vars/* /etc/yum/vars/* 2>/dev/null
      echo "--- RHUI client cert files ---";       ls -lR /etc/pki/rhui/ 2>/dev/null
      echo "--- RHUI endpoint reachability ---"
      curl -sS -o /dev/null -w 'HTTP %{http_code}  ip=%{remote_ip}  time=%{time_total}s\n' \
        --max-time 30 https://rhui4-1.microsoft.com/pulp/repos/ 2>&1
      echo "--- enabled repos (verbose) ---";      yum -v repolist 2>&1 | sed -n '1,40p'
    ) || true
    echo "==================== end RHUI diagnostics (${phase}) ===================="
  } >&2
  return 0
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
export NEO4J_ACCEPT_LICENSE_AGREEMENT=yes
# Pre-install baseline of RHUI/repo state (read-only; does not affect the deploy).
rhui_diagnostics "pre-install"
# Readiness gate: refresh repo metadata first (installs nothing); retried because
# Azure RHUI can return errors on repomd.xml. On persistent failure, dump
# diagnostics before exiting so the extension log shows exactly what broke.
retry yum -y makecache               || { rhui_diagnostics "makecache-failed"; exit 1; }
retry yum -y install neo4j-enterprise || { rhui_diagnostics "install-failed"; exit 1; }

echo "Configuring network in neo4j.conf..."

sed -i 's/#dbms.default_listen_address=0.0.0.0/dbms.default_listen_address=0.0.0.0/g' /etc/neo4j/neo4j.conf
nodeIndex=`curl -H Metadata:true "http://169.254.169.254/metadata/instance/compute?api-version=2017-03-01" \
  | jq ".name" \
  | sed 's/.*_//' \
  | sed 's/"//'`

# VMSS instances often have no instance-level public IP. Prefer public IP when
# available, then fall back to private IP, then hostname so we never write an
# empty advertised address.
EXTERNALIP="$(curl -s -H "Metadata: true" "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/publicIpAddress?api-version=2021-02-01&format=text" || true)"
if [ -z "$EXTERNALIP" ]; then
  EXTERNALIP="$(curl -s -H "Metadata: true" "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/privateIpAddress?api-version=2021-02-01&format=text" || true)"
fi
if [ -z "$EXTERNALIP" ]; then
  EXTERNALIP="$(hostname -f 2>/dev/null || hostname 2>/dev/null || true)"
fi
if [ -z "$EXTERNALIP" ]; then
  echo "ERROR: Could not determine advertised address from IMDS or hostname." >&2
  exit 1
fi
echo ADVERTISED_HOST: $EXTERNALIP

sed -i "s/#server.default_listen_address=0.0.0.0/server.default_listen_address=0.0.0.0/g" /etc/neo4j/neo4j.conf
sed -i "s/#server.default_advertised_address=localhost/server.default_advertised_address=$EXTERNALIP/g" /etc/neo4j/neo4j.conf
sed -i "s/#server.bolt.listen_address=:7687/server.bolt.listen_address=0.0.0.0:7687/g" /etc/neo4j/neo4j.conf
sed -i "s/#server.bolt.advertised_address=:7687/server.bolt.advertised_address=$EXTERNALIP:7687/g" /etc/neo4j/neo4j.conf
sed -i "s/#server.http.listen_address=:7474/server.http.listen_address=0.0.0.0:7474/g" /etc/neo4j/neo4j.conf
sed -i "s/#server.http.advertised_address=:7474/server.http.advertised_address=$EXTERNALIP:7474/g" /etc/neo4j/neo4j.conf

if [[ $nodeCount == 1 ]]; then
  echo "Running on a single node."
else
  echo "Running on multiple nodes."

  sed -i "s/#initial.dbms.default_primaries_count=1/initial.dbms.default_primaries_count=3/g" /etc/neo4j/neo4j.conf

  INTERNALIP=$(curl -s -H "Metadata: true" "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/privateIpAddress?api-version=2021-02-01&format=text")
  echo INTERNALIP: $INTERNALIP

  sed -i "s/#server.cluster.listen_address=:6000/server.cluster.listen_address=0.0.0.0:6000/g" /etc/neo4j/neo4j.conf
  sed -i "s/#server.cluster.advertised_address=:6000/server.cluster.advertised_address=$INTERNALIP:6000/g" /etc/neo4j/neo4j.conf
  sed -i "s/#server.routing.listen_address=:7688/server.routing.listen_address=0.0.0.0:7688/g" /etc/neo4j/neo4j.conf
  sed -i "s/#server.routing.advertised_address=:7688/server.routing.advertised_address=$INTERNALIP:7688/g" /etc/neo4j/neo4j.conf
  sed -i "s/#server.cluster.raft.listen_address=:7000/server.cluster.raft.listen_address=0.0.0.0:7000/g" /etc/neo4j/neo4j.conf
  sed -i "s/#server.cluster.raft.advertised_address=:7000/server.cluster.raft.advertised_address=$INTERNALIP:7000/g" /etc/neo4j/neo4j.conf

  echo "Configuring membership in neo4j.conf..."
  COREMEMBERS="10.0.0.4:6000,10.0.0.5:6000,10.0.0.6:6000"
  sed -i "s/#dbms.cluster.endpoints=localhost:6000,localhost:6001,localhost:6002/dbms.cluster.endpoints=$COREMEMBERS/g" /etc/neo4j/neo4j.conf
fi

echo "Starting Neo4j..."
neo4j-admin dbms set-initial-password "$password"

# The RPM creates this script which does OS checks that incorrectly fail on Azure RH platform images.  Neo4j eng is working on a fix.
rm -f /etc/init.d/neo4j

systemctl enable neo4j
service neo4j start
