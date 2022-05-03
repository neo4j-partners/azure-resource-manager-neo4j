#!/usr/bin/env bash

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

echo "Using the settings:"
echo adminUsername \'$adminUsername\'
echo adminPassword \'$adminPassword\'
echo uniqueString \'$uniqueString\'
echo location \'$location\'
echo graphDatabaseVersion \'$graphDatabaseVersion\'
echo installGraphDataScience \'$installGraphDataScience\'
echo graphDataScienceLicenseKey \'$graphDataScienceLicenseKey\'
echo installBloom \'$installBloom\'
echo bloomLicenseKey \'$bloomLicenseKey\'
echo nodeCount \'$nodeCount\'

echo "Turning off firewalld"
systemctl stop firewalld
systemctl disable firewalld

echo Adding neo4j yum repo...
rpm --import https://debian.neo4j.com/neotechnology.gpg.key
echo "
[neo4j]
name=Neo4j Yum Repo
baseurl=http://yum.neo4j.com/stable
enabled=1
gpgcheck=1" > /etc/yum.repos.d/neo4j.repo

echo Installing Graph Database...
export NEO4J_ACCEPT_LICENSE_AGREEMENT=yes
yum -y install neo4j-enterprise-${graphDatabaseVersion}

echo Installing APOC...
mv /var/lib/neo4j/labs/apoc-*-core.jar /var/lib/neo4j/plugins

echo Configuring extensions and security in neo4j.conf...
sed -i s~#dbms.unmanaged_extension_classes=org.neo4j.examples.server.unmanaged=/examples/unmanaged~dbms.unmanaged_extension_classes=com.neo4j.bloom.server=/bloom,semantics.extension=/rdf~g /etc/neo4j/neo4j.conf
sed -i s/#dbms.security.procedures.unrestricted=my.extensions.example,my.procedures.*/dbms.security.procedures.unrestricted=gds.*,bloom.*/g /etc/neo4j/neo4j.conf
sed -i '$a dbms.security.http_auth_allowlist=/,/browser.*,/bloom.*' /etc/neo4j/neo4j.conf
sed -i '$a dbms.security.procedures.allowlist=apoc.*,gds.*,bloom.*' /etc/neo4j/neo4j.conf

echo Configuring network in neo4j.conf...
sed -i 's/#dbms.default_listen_address=0.0.0.0/dbms.default_listen_address=0.0.0.0/g' /etc/neo4j/neo4j.conf
nodeIndex=`curl -H Metadata:true "http://169.254.169.254/metadata/instance/compute?api-version=2017-03-01" \
  | jq ".name" \
  | sed 's/.*_//' \
  | sed 's/"//'`
publicHostname='vm'$nodeIndex'.node-'$uniqueString'.'$location'.cloudapp.azure.com'
sed -i s/#dbms.default_advertised_address=localhost/dbms.default_advertised_address=${publicHostname}/g /etc/neo4j/neo4j.conf

echo "Adding entries to /etc/hosts to route cluster traffic internally..."
echo "
# Route cluster traffic internally
10.0.0.4 vm0.node-${uniqueString}.${location}.cloudapp.azure.com
10.0.0.5 vm1.node-${uniqueString}.${location}.cloudapp.azure.com
10.0.0.6 vm2.node-${uniqueString}.${location}.cloudapp.azure.com
" >> /etc/hosts

if [[ $nodeCount == 1 ]]; then
  echo Running on a single node.
else
  echo Running on multiple nodes.  Configuring membership in neo4j.conf...
  coreMembers='vm0X,vm1X,vm2X'
  coreMembers=$(echo $coreMembers | sed 's/X/.node-'$uniqueString'.'$location'.cloudapp.azure.com:5000/g')
  sed -i s/#causal_clustering.initial_discovery_members=localhost:5000,localhost:5001,localhost:5002/causal_clustering.initial_discovery_members=${coreMembers}/g /etc/neo4j/neo4j.conf
  sed -i s/#dbms.mode=CORE/dbms.mode=CORE/g /etc/neo4j/neo4j.conf
fi

echo Turning on SSL...
sed -i 's/dbms.connector.https.enabled=false/dbms.connector.https.enabled=true/g' /etc/neo4j/neo4j.conf

#### Todo - Any reason we're not running this line?
#sed -i 's/#dbms.connector.bolt.tls_level=DISABLED/dbms.connector.bolt.tls_level=OPTIONAL/g' /etc/neo4j/neo4j.conf

answers() {
echo --
echo SomeState
echo SomeCity
echo SomeOrganization
echo SomeOrganizationalUnit
echo localhost.localdomain
echo root@localhost.localdomain
}
answers | /usr/bin/openssl req -newkey rsa:2048 -keyout private.key -nodes -x509 -days 365 -out public.crt

### Todo - turn on cluster and backup
#for service in bolt https cluster backup; do
for service in https; do
  sed -i s/#dbms.ssl.policy.${service}/dbms.ssl.policy.${service}/g /etc/neo4j/neo4j.conf
  mkdir -p /var/lib/neo4j/certificates/${service}/trusted
  mkdir -p /var/lib/neo4j/certificates/${service}/revoked
  cp private.key /var/lib/neo4j/certificates/${service}
  cp public.crt /var/lib/neo4j/certificates/${service}
done

chown -R neo4j:neo4j /var/lib/neo4j/certificates
chmod -R 755 /var/lib/neo4j/certificates

if [[ $installGraphDataScience == True && $nodeCount == 1 ]]; then
  echo Installing Graph Data Science...
  cp /var/lib/neo4j/products/neo4j-graph-data-science-*.jar /var/lib/neo4j/plugins
fi

if [[ $graphDataScienceLicenseKey != None ]]; then
  echo Writing GDS license key...
  mkdir -p /etc/neo4j/licenses
  echo $graphDataScienceLicenseKey > /etc/neo4j/licenses/neo4j-gds.license
  sed -i '$a gds.enterprise.license_file=/etc/neo4j/licenses/neo4j-gds.license' /etc/neo4j/neo4j.conf
fi

if [[ $installBloom == True ]]; then
  echo Installing Bloom...
  cp /var/lib/neo4j/products/bloom-plugin-*.jar /var/lib/neo4j/plugins
fi

if [[ $bloomLicenseKey != None ]]; then
  echo Writing Bloom license key...
  mkdir -p /etc/neo4j/licenses
  echo $bloomLicenseKey > /etc/neo4j/licenses/neo4j-bloom.license
  sed -i '$a neo4j.bloom.license_file=/etc/neo4j/licenses/neo4j-bloom.license' /etc/neo4j/neo4j.conf
fi

echo Starting Neo4j...
service neo4j start
neo4j-admin set-initial-password ${adminPassword}