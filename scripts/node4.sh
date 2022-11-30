#!/usr/bin/env bash
set -euo pipefail

echo "Running node4.sh"

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

echo "Turning off firewalld"
systemctl stop firewalld
systemctl disable firewalld

#Format and mount the data disk to /var/lib/neo4j
MOUNT_POINT="/var/lib/neo4j"

DATA_DISK_DEVICE=$(parted -l 2>&1 | grep Error | awk {'print $2'} | sed 's/\://')

sudo parted $DATA_DISK_DEVICE --script mklabel gpt mkpart xfspart xfs 0% 100%
sudo mkfs.xfs $DATA_DISK_DEVICE\1
sudo partprobe $DATA_DISK_DEVICE\1
mkdir $MOUNT_POINT

DATA_DISK_UUID=$(blkid | grep $DATA_DISK_DEVICE\1 | awk {'print $2'} | sed s/\"//g)

echo "$DATA_DISK_UUID $MOUNT_POINT xfs defaults 0 0" >> /etc/fstab

systemctl daemon-reload
mount -a


install_azure_from_dnf() {

  sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
  sudo dnf install -y https://packages.microsoft.com/config/rhel/8/packages-microsoft-prod.rpm
echo -e "[azure-cli]
name=Azure CLI
baseurl=https://packages.microsoft.com/yumrepos/azure-cli
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc" | sudo tee /etc/yum.repos.d/azure-cli.repo
sudo dnf install -y azure-cli
}

perform_az_login() {
  echo "Performing az login"
  az login --identity -u "${azLoginIdentity}"
}

install_neo4j_from_yum() {

  echo "Adding neo4j yum repo..."
  rpm --import https://debian.neo4j.com/neotechnology.gpg.key
  echo "
[neo4j]
name=Neo4j Yum Repo
baseurl=http://yum.neo4j.com/stable/4.4
enabled=1
gpgcheck=1" > /etc/yum.repos.d/neo4j.repo

  echo "Installing Graph Database..."
  export NEO4J_ACCEPT_LICENSE_AGREEMENT=yes
  get_latest_neo4j_version
  echo "printing neo4j version ${neo4j_version}"
  yum -y install neo4j-enterprise-"${neo4j_version}"
  systemctl enable neo4j
}

install_apoc_plugin() {
  echo "Installing APOC..."
  mv /var/lib/neo4j/labs/apoc-*-core.jar /var/lib/neo4j/plugins
}

get_latest_neo4j_version() {
  echo "Getting latest neo4j version"
  neo4j_version=$(curl -s --fail http://versions.neo4j-templates.com/target.json | jq -r '.azure."4.4"')
}

configure_graph_data_science() {

  if [[ "${installGraphDataScience}" == True && "${nodeCount}" == 1 ]]; then
    echo "Installing Graph Data Science..."
    cp /var/lib/neo4j/products/neo4j-graph-data-science-*.jar /var/lib/neo4j/plugins
  fi

  if [[ $graphDataScienceLicenseKey != None ]]; then
    echo "Writing GDS license key..."
    mkdir -p /etc/neo4j/licenses
    echo "${graphDataScienceLicenseKey}" > /etc/neo4j/licenses/neo4j-gds.license
    sed -i '$a gds.enterprise.license_file=/etc/neo4j/licenses/neo4j-gds.license' /etc/neo4j/neo4j.conf
  fi
}

configure_bloom() {
  if [[ ${installBloom} == True ]]; then
    echo "Installing Bloom..."
    cp /var/lib/neo4j/products/bloom-plugin-*.jar /var/lib/neo4j/plugins
  fi
  if [[ $bloomLicenseKey != None ]]; then
    echo "Writing Bloom license key..."
    mkdir -p /etc/neo4j/licenses
    echo "${bloomLicenseKey}" > /etc/neo4j/licenses/neo4j-bloom.license
    sed -i '$a neo4j.bloom.license_file=/etc/neo4j/licenses/neo4j-bloom.license' /etc/neo4j/neo4j.conf
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
  service neo4j start
  neo4j-admin set-initial-password "${adminPassword}"
  while [[ \"$(curl -s -o /dev/null -m 3 -L -w '%{http_code}' http://localhost:7474 )\" != \"200\" ]];
    do echo "Waiting for cluster to start"
    sleep 5
  done
}

set_cluster_configs() {
  local -r privateIP="$(hostname -i | awk '{print $NF}')"  
  sed -i s/#dbms.default_advertised_address=localhost/dbms.default_advertised_address=${privateIP}/g /etc/neo4j/neo4j.conf
  sed -i s/#causal_clustering.discovery_listen_address=:5000/causal_clustering.discovery_listen_address=${privateIP}:5000/g /etc/neo4j/neo4j.conf
  sed -i s/#causal_clustering.transaction_listen_address=:6000/causal_clustering.transaction_listen_address=${privateIP}:6000/g /etc/neo4j/neo4j.conf
  sed -i s/#causal_clustering.raft_listen_address=:7000/causal_clustering.raft_listen_address=${privateIP}:7000/g /etc/neo4j/neo4j.conf
  sed -i s/#dbms.connector.bolt.listen_address=:7687/dbms.connector.bolt.listen_address=${privateIP}:7687/g /etc/neo4j/neo4j.conf
  sed -i s/#dbms.connector.http.advertised_address=:7474/dbms.connector.http.advertised_address=${privateIP}:7474/g /etc/neo4j/neo4j.conf
  sed -i s/#dbms.connector.https.advertised_address=:7473/dbms.connector.https.advertised_address=${privateIP}:7473/g /etc/neo4j/neo4j.conf
  sed -i s/#dbms.routing.enabled=false/dbms.routing.enabled=true/g /etc/neo4j/neo4j.conf
  sed -i s/#dbms.routing.advertised_address=:7688/dbms.routing.advertised_address=${privateIP}:7688/g /etc/neo4j/neo4j.conf
  sed -i s/#dbms.routing.listen_address=0.0.0.0:7688/dbms.routing.listen_address=${privateIP}:7688/g /etc/neo4j/neo4j.conf
  echo dbms.routing.default_router=SERVER >> /etc/neo4j/neo4j.conf
}

build_neo4j_conf_file() {
  echo "Configuring network in neo4j.conf..."

  nodeIndex=`curl -H Metadata:true "http://169.254.169.254/metadata/instance/compute?api-version=2017-03-01" \
    | jq ".name" \
    | sed 's/.*_//' \
    | sed 's/"//'`

  publicHostname='vm'$nodeIndex'.node-'$uniqueString'.'$location'.cloudapp.azure.com'

  sed -i s/#dbms.default_listen_address=0.0.0.0/dbms.default_listen_address=0.0.0.0/g /etc/neo4j/neo4j.conf
  echo "Configuring memory settings in neo4j.conf..."
  neo4j-admin memrec >> /etc/neo4j/neo4j.conf

  if [[ ${nodeCount} == 1 ]]; then
    echo "Running on a single node."
    sed -i s/#dbms.default_advertised_address=localhost/dbms.default_advertised_address="${publicHostname}"/g /etc/neo4j/neo4j.conf
  else
    echo "Running on multiple nodes.  Configuring membership in neo4j.conf..."
    sed -i s/#dbms.mode=CORE/dbms.mode=CORE/g /etc/neo4j/neo4j.conf
    coreMembers=$(az vmss nic list -g "${resourceGroup}" --vmss-name "${vmScaleSetsName}" | jq '.[] | .ipConfigurations[] | .privateIpAddress' | sed 's/"//g;s/$/:5000/g' | tr '\n' ',' | sed 's/,$//g')
    sed -i s/#causal_clustering.initial_discovery_members=localhost:5000,localhost:5001,localhost:5002/causal_clustering.initial_discovery_members=${coreMembers}/g /etc/neo4j/neo4j.conf
    set_cluster_configs
  fi
}

install_azure_from_dnf
perform_az_login
install_neo4j_from_yum
install_apoc_plugin
extension_config
build_neo4j_conf_file
configure_graph_data_science
configure_bloom
start_neo4j
