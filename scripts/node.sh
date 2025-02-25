#!/usr/bin/env bash
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

echo "Turning off firewalld"
systemctl stop firewalld
systemctl disable firewalld

#Format and mount the data disk to /var/lib/neo4j
MOUNT_POINT="/var/lib/neo4j"

DATA_DISK_DEVICE=$(sudo parted -l 2>&1 | grep Error | awk {'print $2'} | sed 's/\://')

sudo parted $DATA_DISK_DEVICE --script mklabel gpt mkpart xfspart xfs 0% 100%
sudo mkfs.xfs $DATA_DISK_DEVICE\1
sudo partprobe $DATA_DISK_DEVICE\1
sudo mkdir $MOUNT_POINT

DATA_DISK_UUID=$(sudo blkid | grep $DATA_DISK_DEVICE\1 | awk {'print $2'} | sed s/\"//g)

echo "$DATA_DISK_UUID $MOUNT_POINT xfs defaults 0 0" | sudo tee -a /etc/fstab

sudo systemctl daemon-reload
sudo mount -a


install_azure_from_dnf() {
    sudo dnf remove -y $(rpm -qa | grep -i rhui)
    sudo rm -f /etc/yum.repos.d/rh-cloud.repo
    sudo rm -f /etc/yum.repos.d/rhui-microsoft-azure-rhel9.repo
    sudo rm -f /etc/yum.repos.d/rhui-load-balancers.conf

    cat << EOF | sudo tee /etc/yum.repos.d/ubi.repo
[ubi-9-baseos]
name=Red Hat Universal Base Image 9 - BaseOS
baseurl=https://cdn-ubi.redhat.com/content/public/ubi/dist/ubi9/9/x86_64/baseos/os
enabled=1
gpgcheck=0

[ubi-9-appstream]
name=Red Hat Universal Base Image 9 - AppStream
baseurl=https://cdn-ubi.redhat.com/content/public/ubi/dist/ubi9/9/x86_64/appstream/os
enabled=1
gpgcheck=0
EOF

    # Remove existing Microsoft repository configuration
    sudo rm -f /etc/yum.repos.d/microsoft-prod.repo
    sudo rm -f /etc/yum.repos.d/microsoft.repo

    for i in {1..3}; do
        if sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc; then
            break
        fi
        sleep 5
    done

    # Add Microsoft repository with gpgcheck disabled initially
    cat << EOF | sudo tee /etc/yum.repos.d/microsoft.repo
[packages-microsoft-com-prod]
name=Microsoft Products
baseurl=https://packages.microsoft.com/rhel/9/prod/
enabled=1
gpgcheck=0
EOF
    sudo chmod +x /usr/local/bin/az

    # Clean and update DNF cache
    sudo dnf clean all
    sudo dnf makecache

    # Install Azure CLI
    sudo dnf install -y azure-cli

    # Re-enable gpgcheck after installation
    sudo sed -i 's/gpgcheck=0/gpgcheck=1/' /etc/yum.repos.d/microsoft.repo
}

perform_az_login() {
  echo "Checking if Azure CLI is installed..."
  if command -v az &> /dev/null; then
    echo "Azure CLI is installed. Performing az login..."
    az login --identity -u "${azLoginIdentity}"
  else
    echo "Azure CLI is not installed. Skipping az login."

  fi
}

install_neo4j_from_yum() {

  echo "Adding neo4j yum repo..."
  sudo rpm --import https://debian.neo4j.com/neotechnology.gpg.key
echo "
[neo4j]
name=Neo4j Yum Repo
baseurl=http://yum.neo4j.com/stable/5
enabled=1
gpgcheck=1" | sudo tee /etc/yum.repos.d/neo4j.repo

  echo "Installing Graph Database..."
sudo NEO4J_ACCEPT_LICENSE_AGREEMENT=yes yum -y install neo4j-enterprise-"${graphDatabaseVersion}"
export JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java))))
echo "export JAVA_HOME=$JAVA_HOME" | sudo tee -a /etc/profile.d/java.sh
  sudo systemctl enable neo4j
}

install_apoc_plugin() {
  echo "Installing APOC..."
  mv /var/lib/neo4j/labs/apoc-*-core.jar /var/lib/neo4j/plugins
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
    sed -i '$a dbms.bloom.license_file=/etc/neo4j/licenses/neo4j-bloom.license' /etc/neo4j/neo4j.conf
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
  sudo systemctl start neo4j
  neo4j-admin dbms set-initial-password "${adminPassword}"
  while [[ \"$(curl -s -o /dev/null -m 3 -L -w '%{http_code}' http://localhost:7474 )\" != \"200\" ]];
    do echo "Waiting for cluster to start"
    sleep 5
  done
}

build_neo4j_conf_file() {
  local -r privateIP="$(hostname -i | awk '{print $NF}')"
  echo "Configuring network in neo4j.conf..."

  nodeIndex=`curl -H Metadata:true "http://169.254.169.254/metadata/instance/compute?api-version=2017-03-01" \
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

  if [[ ${nodeCount} == 1 ]]; then
    echo "Running on a single node."
  else
    echo "Running on multiple nodes.  Configuring membership in neo4j.conf..."
    sed -i s/#initial.dbms.default_primaries_count=1/initial.dbms.default_primaries_count=3/g /etc/neo4j/neo4j.conf
    sed -i s/#initial.dbms.default_secondaries_count=0/initial.dbms.default_secondaries_count=$(expr ${nodeCount} - 3)/g /etc/neo4j/neo4j.conf
    sed -i s/#server.bolt.listen_address=:7687/server.bolt.listen_address="${privateIP}":7687/g /etc/neo4j/neo4j.conf
    echo "dbms.cluster.minimum_initial_system_primaries_count=${nodeCount}" >> /etc/neo4j/neo4j.conf
    coreMembers=$(az vmss nic list -g "${resourceGroup}" --vmss-name "${vmScaleSetsName}" | jq '.[] | .ipConfigurations[] | .privateIpAddress' | sed 's/"//g;s/$/:5000/g' | tr '\n' ',' | sed 's/,$//g')
    sed -i s/#dbms.cluster.discovery.endpoints=localhost:5000,localhost:5001,localhost:5002/dbms.cluster.discovery.endpoints="${coreMembers}"/g /etc/neo4j/neo4j.conf
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
