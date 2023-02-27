#!/usr/bin/env bash
set -euo pipefail

echo "Running node.sh"

adminUsername=$1
adminPassword=$2
uniqueString=$3
location=$4
graphDatabaseVersion=$5
azLoginIdentity=$6
resourceGroup=$7
vmScaleSetsName=$8

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
baseurl=https://yum.neo4j.com/stable/5
enabled=1
gpgcheck=1
EOF

  echo "Installing Graph Database..."

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

get_vmss_tags() {
  taggedNeo4jVersion=$(az vmss list --resource-group ${resourceGroup} | jq --arg vmssName "${vmScaleSetsName}" '.[] | select(.name==$vmssName).tags.Neo4jVersion')
  echo "Tagged Neo4j Version ${taggedNeo4jVersion}"
}

set_vmss_tags() {
  installed_neo4j_version=$(/usr/bin/neo4j --version)
  echo "Installed neo4j version is ${installed_neo4j_version}. Trying to set vmss tags"
  resourceId=$(az vmss list --resource-group "${resourceGroup}" | jq -r '.[] | .id')
  az tag create --tags Neo4jVersion="${installed_neo4j_version}" --resource-id "${resourceId}"
  echo "Added tag Neo4jVersion=${installed_neo4j_version}"
}

set_yum_pkg() {
    yumPkg="neo4j"
    get_vmss_tags
    if [[ -z "${taggedNeo4jVersion}" || "${taggedNeo4jVersion}" == "null" ]]; then
      get_latest_neo4j_version
      if [[ ! -z "${latest_neo4j_version}" ]]; then
        yumPkg="neo4j-${latest_neo4j_version}"
      fi
    else
      yumPkg="neo4j-${taggedNeo4jVersion}"
    fi
    echo "Installing the yumpkg ${yumPkg}"
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

build_neo4j_conf_file() {
  local -r privateIP="$(hostname -i | awk '{print $NF}')"
  echo "Configuring network in neo4j.conf..."

  local -r nodeIndex=`curl -H Metadata:true "http://169.254.169.254/metadata/instance/compute?api-version=2017-03-01" \
    | jq ".name" \
    | sed 's/.*_//' \
    | sed 's/"//'`

  publicHostname='vm'$nodeIndex'.node-'$uniqueString'.'$location'.cloudapp.azure.com'


  sed -i s/#server.default_listen_address=0.0.0.0/server.default_listen_address=0.0.0.0/g /etc/neo4j/neo4j.conf
  sed -i s/#server.default_advertised_address=localhost/server.default_advertised_address="${publicHostname}"/g /etc/neo4j/neo4j.conf
  sed -i s/#server.discovery.advertised_address=:5000/server.discovery.advertised_address="${privateIP}":5000/g /etc/neo4j/neo4j.conf
  sed -i s/#server.routing.advertised_address=:7688/server.routing.advertised_address="${privateIP}":7688/g /etc/neo4j/neo4j.conf
  sed -i s/#server.discovery.listen_address=:5000/server.discovery.listen_address="${privateIP}":5000/g /etc/neo4j/neo4j.conf
  sed -i s/#server.routing.listen_address=0.0.0.0:7688/server.routing.listen_address="${privateIP}":7688/g /etc/neo4j/neo4j.conf
  sed -i s/#server.bolt.listen_address=:7687/server.bolt.listen_address="${privateIP}":7687/g /etc/neo4j/neo4j.conf
  sed -i s/#server.bolt.advertised_address=:7687/server.bolt.advertised_address="${publicHostname}":7687/g /etc/neo4j/neo4j.conf
  neo4j-admin server memory-recommendation >> /etc/neo4j/neo4j.conf

  #this is to prevent SSRF attacks
  #Read more here https://neo4j.com/developer/kb/protecting-against-ssrf/
  echo "internal.dbms.cypher_ip_blocklist=10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,169.254.169.0/24,fc00::/7,fe80::/10,ff00::/8" >> /etc/neo4j/neo4j.conf

}

mount_data_disk
install_azure_from_dnf
perform_az_login
install_neo4j_from_yum
install_apoc_plugin
extension_config
build_neo4j_conf_file
start_neo4j
set_vmss_tags
