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

install_azure_from_dnf() {

  sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
  # Comment out the next line, as it conflicts on RHEL9:
  #sudo dnf install -y https://packages.microsoft.com/config/rhel/9/packages-microsoft-prod.rpm

  cat <<EOF >/etc/yum.repos.d/azure-cli.repo
[azure-cli]
name=Azure CLI
baseurl=https://packages.microsoft.com/yumrepos/azure-cli
enabled=1
gpgcheck=0
EOF

# Use --nobest and --skip-broken to avoid dependency conflicts
sudo dnf install -y --nobest --skip-broken azure-cli
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

get_vmss_tags() {
  taggedNeo4jVersion=$(az vmss list --resource-group ${resourceGroup} | jq --arg vmssName "${vmScaleSetsName}" '.[] | select(.name==$vmssName).tags.Neo4jVersion')
  echo "Tagged Neo4j Version ${taggedNeo4jVersion}"
}

set_vmss_tags() {
  installed_neo4j_version=$(/usr/bin/neo4j --version)
  echo "Installed neo4j version is ${installed_neo4j_version}. Trying to set vmss tags"
  
  # Try to set the tag but don't fail if it doesn't work
  if resourceId=$(az vmss list --resource-group "${resourceGroup}" | jq -r '.[] | .id' 2>/dev/null); then
    echo "Found resource ID: ${resourceId}"
    if az tag create --tags Neo4jVersion="${installed_neo4j_version}" --resource-id "${resourceId}" 2>/dev/null; then
      echo "Added tag Neo4jVersion=${installed_neo4j_version}"
    else
      echo "WARNING: Failed to add tag Neo4jVersion=${installed_neo4j_version}, but continuing anyway"
    fi
  else
    echo "WARNING: Failed to get resource ID for tagging, but continuing anyway"
  fi
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
  echo "Fetching VM private IPs from Azure VMSS..."

  coreMembers=""
  
  # Get all VMs in the scale set and their private IPs
  # Add error handling with a timeout
  local vmIPs=""
  local max_retries=3
  local retry_count=0
  
  while [[ $retry_count -lt $max_retries ]]; do
    echo "Attempt $((retry_count+1)) to fetch VM IPs..."
    vmIPs=$(az vmss nic list --resource-group "${resourceGroup}" --vmss-name "${vmScaleSetsName}" 2>/dev/null | \
      jq -r '.[].ipConfigurations[0].privateIpAddress' 2>/dev/null | sort)
    
    if [[ ! -z "$vmIPs" ]]; then
      break
    fi
    
    retry_count=$((retry_count+1))
    if [[ $retry_count -lt $max_retries ]]; then
      echo "Failed to fetch IPs, retrying in 5 seconds..."
      sleep 5
    fi
  done
  
  # Check if we got any IPs
  if [[ -z "$vmIPs" ]]; then
    echo "ERROR: Could not fetch private IPs from Azure after $max_retries attempts."
    echo "This script requires the ability to fetch VM IPs from Azure CLI."
    exit 1
  else
    echo "Successfully fetched VM IPs: $vmIPs"
    # Build the core members string from the fetched IPs
    for ip in $vmIPs; do
      if [[ -z "$coreMembers" ]]; then
        coreMembers="${ip}:6000"
      else
        coreMembers="${coreMembers},${ip}:6000"
      fi
    done
  fi

  echo "Final core members: $coreMembers"
}


build_neo4j_conf_file() {
  echo "Getting private IP using hostname -i..."
  local privateIP="$(hostname -i | awk '{print $NF}')"
  
  # Validate the IP
  if [[ -z "$privateIP" || "$privateIP" == "127.0.0.1" ]]; then
    echo "ERROR: Failed to get a valid private IP using hostname -i"
    echo "Got: $privateIP"
    echo "This script requires a valid private IP to configure Neo4j."
    exit 1
  fi
  
  echo "Using private IP: ${privateIP}"
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
    echo "Running on multiple nodes. Configuring membership in neo4j.conf..."
    sed -i s/#initial.dbms.default_primaries_count=1/initial.dbms.default_primaries_count=3/g /etc/neo4j/neo4j.conf
    sed -i s/#initial.dbms.default_secondaries_count=0/initial.dbms.default_secondaries_count=$(expr ${nodeCount} - 3)/g /etc/neo4j/neo4j.conf
    
    # Listen for Bolt on the private IP
    sed -i s/#server.bolt.listen_address=:7687/server.bolt.listen_address="${privateIP}":7687/g /etc/neo4j/neo4j.conf
    
    # Set minimum_initial_system_primaries_count to the total nodeCount
    echo "dbms.cluster.minimum_initial_system_primaries_count=${nodeCount}" >> /etc/neo4j/neo4j.conf

    # Fetch core members from Azure VMSS NICs (see function below)
    get_core_members
    echo "$(date) outside func, Printing coreMembers: ${coreMembers}"

    # Append discovery settings at the end of neo4j.conf using the coreMembers list
    sed -i -e '$a\dbms.cluster.discovery.version=V2_ONLY' \
           -e '$a\dbms.cluster.discovery.resolver_type=LIST' \
           -e "\$a\dbms.cluster.discovery.v2.endpoints=${coreMembers}" \
           /etc/neo4j/neo4j.conf
fi

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