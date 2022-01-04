#!/usr/bin/env bash

echo "Running node.sh"

adminUsername=$1
adminPassword=$2
uniqueString=$3
licenseKey=$4
location=$5
graphDatabaseVersion=$6
graphDataScienceVersion=$7
bloomVersion=$8
nodeCount=$9

echo "Using the settings:"
echo adminUsername \'$adminUsername\'
echo adminPassword \'$adminPassword\'
echo uniqueString \'$uniqueString\'
echo licenseKey \'$licenseKey\'
echo location \'$location\'
echo graphDatabaseVersion \'$graphDatabaseVersion\'
echo graphDataScienceVersion \'$graphDataScienceVersion\'
echo bloomVersion \'$bloomVersion\'
echo nodeCount \'$nodeCount\'

echo Adding neo4j yum repo...
rpm --import https://debian.neo4j.com/neotechnology.gpg.key
echo "
[neo4j]
name=Neo4j Yum Repo
baseurl=http://yum.neo4j.com/stable
enabled=1
gpgcheck=1" > /etc/yum.repos.d/neo4j.repo

echo Writing neo4j license key file...
mkdir /etc/neo4j/license
echo $licenseKey > /etc/neo4j/license/neo4j.license

echo Installing Graph Database...
export NEO4J_ACCEPT_LICENSE_AGREEMENT=yes
yum -y install neo4j-enterprise-${graphDatabaseVersion}

echo Configuring network in neo4j.conf...
sed -i 's/#dbms.default_listen_address=0.0.0.0/dbms.default_listen_address=0.0.0.0/g' /etc/neo4j/neo4j.conf
nodeIndex=`curl -H Metadata:true "http://169.254.169.254/metadata/instance/compute?api-version=2017-03-01" \
  | jq ".name" \
  | sed 's/.*_//' \
  | sed 's/"//'`
publicHostname='vm0.node-'$uniqueString'.'$location'.cloudapp.azure.com'
sed -i s/#dbms.default_advertised_address=localhost/dbms.default_advertised_address=${publicHostname}/g /etc/neo4j/neo4j.conf

if [[ \"$nodeCount\" == 1 ]]; then
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

#for service in bolt https cluster backup; do
for service in https; do
  sed -i \"s/#dbms.ssl.policy.${service}/dbms.ssl.policy.${service}/g\" /etc/neo4j/neo4j.conf
  mkdir -p /var/lib/neo4j/certificates/${service}/trusted
  mkdir -p /var/lib/neo4j/certificates/${service}/revoked
  cp private.key /var/lib/neo4j/certificates/${service}
  cp public.crt /var/lib/neo4j/certificates/${service}
done

chown -R neo4j:neo4j /var/lib/neo4j/certificates
chmod -R 755 /var/lib/neo4j/certificates

if [[ \"$graphDataScienceVersion\" != "None" ]]; then
  echo Installing Graph Data Science...
  curl \"https://s3-eu-west-1.amazonaws.com/com.neo4j.graphalgorithms.dist/graph-data-science/neo4j-graph-data-science-${graphDataScienceVersion}-standalone.zip\" -o neo4j-graph-data-science-${graphDataScienceVersion}-standalone.zip
  unzip neo4j-graph-data-science-${graphDataScienceVersion}-standalone.zip
  mv neo4j-graph-data-science-${graphDataScienceVersion}.jar /var/lib/neo4j/plugins
fi

if [[ \"$bloomVersion\" != "None" ]]; then
  echo Installing Bloom...
  curl -L \"https://neo4j.com/artifact.php?name=neo4j-bloom-${bloomVersion}.zip\" -o neo4j-bloom-${bloomVersion}.zip
  unzip neo4j-bloom-${bloomVersion}.zip
  mv \"bloom-plugin-4.x-${bloomVersion}.jar\" /var/lib/neo4j/plugins
fi

echo Configuring Graph Data Science and Bloom in neo4j.conf...
sed -i s/#dbms.security.procedures.unrestricted=my.extensions.example,my.procedures.*/dbms.security.procedures.unrestricted=gds.*,bloom.*/g /etc/neo4j/neo4j.conf
sed -i s/#dbms.security.procedures.allowlist=apoc.coll.*,apoc.load.*,gds.*/dbms.security.procedures.allowlist=apoc.coll.*,apoc.load.*,gds.*,bloom.*/g /etc/neo4j/neo4j.conf

echo Starting Neo4j...
service neo4j start
neo4j-admin set-initial-password ${adminPassword}