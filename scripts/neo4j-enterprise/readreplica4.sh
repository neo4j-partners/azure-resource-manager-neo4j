#!/usr/bin/env bash
#
# Script:      readreplica4.sh
# Purpose:     This script is used to install Neo4j 4.4.x Community on Azure VM's

set -euo pipefail

echo "Running readreplica4.sh"

adminPassword=$1
azLoginIdentity=$2
resourceGroup=$3
vmScaleSetsName=$4
installGraphDataScience=$5
graphDataScienceLicenseKey=$6
installBloom=$7
bloomLicenseKey=$8

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


install_azure_from_dnf() {

  sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
  sudo dnf install -y https://packages.microsoft.com/config/rhel/8/packages-microsoft-prod.rpm
  cat <<EOF >/etc/yum.repos.d/azure-cli.repo
[azure-cli]
name=Azure CLI
baseurl=https://packages.microsoft.com/yumrepos/azure-cli
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF

  sudo dnf install -y azure-cli
}

perform_az_login() {
  echo "Performing az login"
  az login --identity -u "${azLoginIdentity}"
}

install_neo4j_from_yum() {

  echo "Adding neo4j yum repo..."
  rpm --import https://debian.neo4j.com/neotechnology.gpg.key

  cat <<EOF >/etc/yum.repos.d/neo4j.repo
[neo4j]
name=Neo4j Yum Repo
baseurl=http://yum.neo4j.com/stable/4.4
enabled=1
gpgcheck=1
EOF

  echo "Installing Graph Database..."
  export NEO4J_ACCEPT_LICENSE_AGREEMENT=yes
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
  latest_neo4j_version=$(curl -s --fail http://versions.neo4j-templates.com/target.json | jq -r '.azure."4.4"' || echo "")
  echo "Latest Neo4j Version is ${latest_neo4j_version}"
}

get_vmss_tags() {
  taggedNeo4jVersion=$(az vmss list --resource-group ${resourceGroup} | jq --arg vmssName "${vmScaleSetsName}" '.[] | select(.name==$vmssName).tags.Neo4jVersion')
  echo "Tagged Neo4j Version ${taggedNeo4jVersion}"
}

set_vmss_tags() {
  installed_neo4j_version=$(/usr/bin/neo4j --version | awk -F " " '{print $2}')
  echo "Installed neo4j version is ${installed_neo4j_version}. Trying to set vmss tags"
  resourceId=$(az vmss list --resource-group "${resourceGroup}" | jq -r '.[] | .id' | grep 'read-replica-vmss')
  az tag create --tags Neo4jVersion="${installed_neo4j_version}" --resource-id "${resourceId}"
  echo "Added tag Neo4jVersion=${installed_neo4j_version}"
}

set_yum_pkg() {
    yumPkg="neo4j-enterprise"
    get_vmss_tags
    if [[ -z "${taggedNeo4jVersion}" || "${taggedNeo4jVersion}" == "null" ]]; then
      get_latest_neo4j_version
      if [[ ! -z "${latest_neo4j_version}" ]]; then
        yumPkg="neo4j-enterprise-${latest_neo4j_version}"
      fi
    else
      yumPkg="neo4j-enterprise-${taggedNeo4jVersion}"
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
    sed -i '$a neo4j.bloom.license_file=/etc/neo4j/licenses/neo4j-bloom.license' /etc/neo4j/neo4j.conf
    chown -R neo4j:neo4j /etc/neo4j/licenses
  fi
}

extension_config() {
  echo Configuring extensions and security in neo4j.conf...
  sed -i s~#dbms.unmanaged_extension_classes=org.neo4j.examples.server.unmanaged=/examples/unmanaged~dbms.unmanaged_extension_classes=com.neo4j.bloom.server=/bloom,semantics.extension=/rdf~g /etc/neo4j/neo4j.conf
  sed -i s/#dbms.security.procedures.unrestricted=my.extensions.example,my.procedures.*/dbms.security.procedures.unrestricted=gds.*,apoc.*,bloom.*/g /etc/neo4j/neo4j.conf
  echo "dbms.security.http_auth_allowlist=/,/browser.*,/bloom.*" >> /etc/neo4j/neo4j.conf
  echo "dbms.security.procedures.allowlist=apoc.*,gds.*,bloom.*" >> /etc/neo4j/neo4j.conf
}

start_neo4j() {
  echo "Starting Neo4j..."
  #service neo4j start
  systemctl start neo4j
  neo4j-admin set-initial-password "${adminPassword}"
  while [[ \"$(curl -s -o /dev/null -m 3 -L -w '%{http_code}' http://localhost:7474 )\" != \"200\" ]];
    do echo "Waiting for cluster to start"
    sleep 5
  done
}

build_neo4j_conf_file() {
  echo "Configuring network in neo4j.conf..."

  local -r privateIP="$(hostname -i | awk '{print $NF}')"

  sed -i s/#dbms.default_listen_address=0.0.0.0/dbms.default_listen_address=0.0.0.0/g /etc/neo4j/neo4j.conf
  echo "Configuring memory settings in neo4j.conf..."
  neo4j-admin memrec >> /etc/neo4j/neo4j.conf

    sed -i s/#dbms.default_advertised_address=localhost/dbms.default_advertised_address="${privateIP}"/g /etc/neo4j/neo4j.conf
    echo "Configuring read replica membership in neo4j.conf..."
    sed -i s/#dbms.mode=CORE/dbms.mode=READ_REPLICA/g /etc/neo4j/neo4j.conf
    coreMembers=$(az vmss nic list -g "${resourceGroup}" --vmss-name "${vmScaleSetsName}" | jq '.[] | .ipConfigurations[] | .privateIPAddress' | sed 's/"//g;s/$/:5000/g' | tr '\n' ',' | sed 's/,$//g')
    sed -i s/#causal_clustering.initial_discovery_members=localhost:5000,localhost:5001,localhost:5002/causal_clustering.initial_discovery_members=${coreMembers}/g /etc/neo4j/neo4j.conf
    sed -i s/#dbms.routing.enabled=false/dbms.routing.enabled=true/g /etc/neo4j/neo4j.conf
    sed -i s/#dbms.routing.advertised_address=:7688/dbms.routing.advertised_address=${privateIP}:7688/g /etc/neo4j/neo4j.conf
    sed -i s/#dbms.routing.listen_address=0.0.0.0:7688/dbms.routing.listen_address=${privateIP}:7688/g /etc/neo4j/neo4j.conf
    echo "dbms.routing.default_router=SERVER" >> /etc/neo4j/neo4j.conf
}

mount_data_disk
install_azure_from_dnf
perform_az_login
install_neo4j_from_yum
install_apoc_plugin
extension_config
build_neo4j_conf_file
configure_graph_data_science
configure_bloom
start_neo4j
set_vmss_tags
