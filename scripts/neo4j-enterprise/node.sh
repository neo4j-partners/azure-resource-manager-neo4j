#!/usr/bin/env bash

#
# Script:      node.sh
# Purpose:     This script is used to install Neo4j 5.x Enterprise on Azure VM's

set -euo pipefail

echo "Running node.sh"

adminUsername=$1
adminPassword=$2
uniqueString=$3
location=$4
graphDatabaseVersion=$5
installGraphDataScience=$6
graphDataScienceLicenseKey=$7
installBloom=$8
bloomLicenseKey=$9
nodeCount=${10}
loadBalancerDNSName=${11}
azLoginIdentity=${12}
resourceGroup=${13}
vmScaleSetsName=${14}
licenseType=${15}

echo "Turning off firewalld"
systemctl stop firewalld
systemctl disable firewalld


mount_data_disk() {
  #Format and mount the data disk to /var/lib/neo4j
  local -r MOUNT_POINT="/var/lib/neo4j"

  local -r DATA_DISK_DEVICE=$(parted -l 2>&1 | grep Error | awk {'print $2'} | sed 's/\://')

  sudo parted $DATA_DISK_DEVICE --script mklabel gpt mkpart xfspart xfs 0% 100%
  sudo mkfs.xfs $DATA_DISK_DEVICE\1
  sudo partprobe $DATA_DISK_DEVICE\1
  mkdir $MOUNT_POINT

  local -r DATA_DISK_UUID=$(blkid | grep $DATA_DISK_DEVICE\1 | awk {'print $2'} | sed s/\"//g)

  echo "$DATA_DISK_UUID $MOUNT_POINT xfs defaults 0 0" >> /etc/fstab

  systemctl daemon-reload
  mount -a
}

install_neo4j_from_yum() {

  echo "Adding neo4j yum repo..."
  rpm --import https://debian.neo4j.com/neotechnology.gpg.key

  cat <<EOF >/etc/yum.repos.d/neo4j.repo
[neo4j]
name=Neo4j Yum Repo
baseurl=https://yum.neo4j.com/stable/5
enabled=1
gpgcheck=1
EOF

  echo "Installing Graph Database..."
  export NEO4J_ACCEPT_LICENSE_AGREEMENT=yes
  if [[ "${licenseType}" == "Evaluation" ]]; then
    export NEO4J_ACCEPT_LICENSE_AGREEMENT="eval"
  fi
  set_yum_pkg
  yum -y install "${yumPkg}"
  systemctl enable neo4j

}

install_apoc_plugin() {
  echo "Installing APOC..."
  mv /var/lib/neo4j/labs/apoc-*-core.jar /var/lib/neo4j/plugins
}

get_latest_neo4j_version() {
  echo "Getting latest neo4j version"
  latest_neo4j_version=$(curl -s --fail http://versions.neo4j-templates.com/target.json | jq -r '.azure."5"' || echo "")
  echo "Latest Neo4j Version is ${latest_neo4j_version}"
}

# REMOVED: Self-tagging functions no longer needed
# Tags are now set directly in ARM template (no custom RBAC roles required)
# get_vmss_tags() { ... }
# set_vmss_tags() { ... }

set_yum_pkg() {
    # Use template parameter directly (no tag lookup needed)
    yumPkg="neo4j-enterprise"

    # Get latest version for the major version specified
    get_latest_neo4j_version
    if [[ ! -z "${latest_neo4j_version}" ]]; then
      yumPkg="neo4j-enterprise-${latest_neo4j_version}"
    fi

    echo "Installing the yumpkg ${yumPkg}"
}

configure_graph_data_science() {
  if [[ "${installGraphDataScience}" == Yes && "${nodeCount}" == 1 ]]; then
    echo "Installing Graph Data Science..."
    cp /var/lib/neo4j/products/neo4j-graph-data-science-*.jar /var/lib/neo4j/plugins
    chown neo4j:neo4j /var/lib/neo4j/plugins/neo4j-graph-data-science-*.jar
  fi

  if [[ $graphDataScienceLicenseKey != None ]]; then
    echo "Writing GDS license key..."
    mkdir -p /etc/neo4j/licenses
    echo "${graphDataScienceLicenseKey}" > /etc/neo4j/licenses/neo4j-gds.license
    sed -i '$a gds.enterprise.license_file=/etc/neo4j/licenses/neo4j-gds.license' /etc/neo4j/neo4j.conf
    chown -R neo4j:neo4j /etc/neo4j/licenses
  fi
}

configure_bloom() {
  if [[ ${installBloom} == Yes ]]; then
    echo "Installing Bloom..."
    cp /var/lib/neo4j/products/bloom-plugin-*.jar /var/lib/neo4j/plugins
    chown neo4j:neo4j /var/lib/neo4j/plugins/bloom-plugin-*.jar
  fi
  if [[ $bloomLicenseKey != None ]]; then
    echo "Writing Bloom license key..."
    mkdir -p /etc/neo4j/licenses
    echo "${bloomLicenseKey}" > /etc/neo4j/licenses/neo4j-bloom.license
    sed -i '$a dbms.bloom.license_file=/etc/neo4j/licenses/neo4j-bloom.license' /etc/neo4j/neo4j.conf
    chown -R neo4j:neo4j /etc/neo4j/licenses
  fi
}

extension_config() {
  echo Configuring extensions and security in neo4j.conf...
  sed -i s~#server.unmanaged_extension_classes=org.neo4j.examples.server.unmanaged=/examples/unmanaged~server.unmanaged_extension_classes=com.neo4j.bloom.server=/bloom,semantics.extension=/rdf~g /etc/neo4j/neo4j.conf
  sed -i s/#dbms.security.procedures.unrestricted=my.extensions.example,my.procedures.*/dbms.security.procedures.unrestricted=gds.*,apoc.*,bloom.*/g /etc/neo4j/neo4j.conf
  echo "dbms.security.http_auth_allowlist=/,/browser.*,/bloom.*" >> /etc/neo4j/neo4j.conf
  echo "dbms.security.procedures.allowlist=apoc.*,gds.*,bloom.*" >> /etc/neo4j/neo4j.conf
}

start_neo4j() {
  echo "Starting Neo4j..."
  #service neo4j start
  systemctl start neo4j
  neo4j-admin dbms set-initial-password "${adminPassword}"
  while [[ \"$(curl -s -o /dev/null -m 3 -L -w '%{http_code}' http://localhost:7474 )\" != \"200\" ]];
    do echo "Waiting for cluster to start"
    sleep 5
  done
}

get_core_members() {
  # Use DNS-based discovery instead of Azure CLI
  # VMSS instances have predictable internal hostnames: vm0, vm1, vm2, etc.
  # These resolve automatically within the virtual network
  echo "$(date) Generating core members using DNS-based discovery"

  coreMembers=""
  for i in $(seq 0 $((nodeCount - 1))); do
    if [ -n "$coreMembers" ]; then
      coreMembers="${coreMembers},"
    fi
    # Internal VMSS hostname pattern: vm{instanceId}
    coreMembers="${coreMembers}vm${i}:5000"
  done

  echo "$(date) Generated core members: ${coreMembers}"
}

build_neo4j_conf_file() {
  local -r privateIP="$(hostname -i | awk '{print $NF}')"
  echo "Configuring network in neo4j.conf..."

  local -r nodeIndex=`curl -H Metadata:true "http://169.254.169.254/metadata/instance/compute?api-version=2017-03-01" \
    | jq ".name" \
    | sed 's/.*_//' \
    | sed 's/"//'`

  if [ "${nodeCount}" == 1 ]; then
    publicHostname='vm'$nodeIndex'.node-'$uniqueString'.'$location'.cloudapp.azure.com'
  else
    publicHostname="${loadBalancerDNSName}"
  fi


  sed -i s/#server.default_listen_address=0.0.0.0/server.default_listen_address=0.0.0.0/g /etc/neo4j/neo4j.conf
  sed -i s/#server.default_advertised_address=localhost/server.default_advertised_address="${publicHostname}"/g /etc/neo4j/neo4j.conf
  sed -i s/#server.discovery.advertised_address=:5000/server.discovery.advertised_address="${privateIP}":5000/g /etc/neo4j/neo4j.conf
  sed -i s/#server.cluster.advertised_address=:6000/server.cluster.advertised_address="${privateIP}":6000/g /etc/neo4j/neo4j.conf
  sed -i s/#server.cluster.raft.advertised_address=:7000/server.cluster.raft.advertised_address="${privateIP}":7000/g /etc/neo4j/neo4j.conf
  sed -i s/#server.routing.advertised_address=:7688/server.routing.advertised_address="${privateIP}":7688/g /etc/neo4j/neo4j.conf
  sed -i s/#server.discovery.listen_address=:5000/server.discovery.listen_address="${privateIP}":5000/g /etc/neo4j/neo4j.conf
  sed -i s/#server.routing.listen_address=0.0.0.0:7688/server.routing.listen_address="${privateIP}":7688/g /etc/neo4j/neo4j.conf
  sed -i s/#server.cluster.listen_address=:6000/server.cluster.listen_address="${privateIP}":6000/g /etc/neo4j/neo4j.conf
  sed -i s/#server.cluster.raft.listen_address=:7000/server.cluster.raft.listen_address="${privateIP}":7000/g /etc/neo4j/neo4j.conf
  sed -i s/#server.bolt.listen_address=:7687/server.bolt.listen_address="${privateIP}":7687/g /etc/neo4j/neo4j.conf
  sed -i s/#server.bolt.advertised_address=:7687/server.bolt.advertised_address="${privateIP}":7687/g /etc/neo4j/neo4j.conf
  neo4j-admin server memory-recommendation >> /etc/neo4j/neo4j.conf
  echo "server.metrics.enabled=true" >> /etc/neo4j/neo4j.conf
  echo "server.metrics.jmx.enabled=true" >> /etc/neo4j/neo4j.conf
  echo "server.metrics.prefix=neo4j" >> /etc/neo4j/neo4j.conf
  echo "server.metrics.filter=*" >> /etc/neo4j/neo4j.conf
  echo "server.metrics.csv.interval=5s" >> /etc/neo4j/neo4j.conf
  echo "dbms.routing.default_router=SERVER" >> /etc/neo4j/neo4j.conf

  #this is to prevent SSRF attacks
  #Read more here https://neo4j.com/developer/kb/protecting-against-ssrf/
  echo "internal.dbms.cypher_ip_blocklist=10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,169.254.169.0/24,fc00::/7,fe80::/10,ff00::/8" >> /etc/neo4j/neo4j.conf

  if [[ ${nodeCount} == 1 ]]; then
    echo "Running on a single node."
  else
    echo "Running on multiple nodes.  Configuring membership in neo4j.conf..."
    sed -i s/#initial.dbms.default_primaries_count=1/initial.dbms.default_primaries_count=3/g /etc/neo4j/neo4j.conf
    sed -i s/#initial.dbms.default_secondaries_count=0/initial.dbms.default_secondaries_count=$(expr ${nodeCount} - 3)/g /etc/neo4j/neo4j.conf
    sed -i s/#server.bolt.listen_address=:7687/server.bolt.listen_address="${privateIP}":7687/g /etc/neo4j/neo4j.conf
    echo "dbms.cluster.minimum_initial_system_primaries_count=${nodeCount}" >> /etc/neo4j/neo4j.conf
    get_core_members
    echo "$(date) outside func , Printing coreMembers ${coreMembers}"
    sed -i s/#dbms.cluster.discovery.endpoints=localhost:5000,localhost:5001,localhost:5002/dbms.cluster.discovery.endpoints="${coreMembers}"/g /etc/neo4j/neo4j.conf
  fi
}

mount_data_disk
# Azure CLI no longer needed - using DNS-based cluster discovery
install_neo4j_from_yum
install_apoc_plugin
extension_config
build_neo4j_conf_file
configure_graph_data_science
configure_bloom
start_neo4j
# set_vmss_tags - REMOVED: Tags now set by ARM template
