#!/usr/bin/env bash

echo "Running node.sh"

adminUsername=$1
adminPassword=$2
uniqueString=$3
licenseKey=$4
location=$5

graphDatabaseVersion
graphDataScienceVersion
bloomVersion
nodeCount

echo "Using the settings:"
echo adminUsername \'$adminUsername\'
echo adminPassword \'$adminPassword\'
echo uniqueString \'$uniqueString\'
echo licenseKey \'$licenseKey\'
echo location \'$location\'

apt-get -y install jq
nodeIndex=`curl -H Metadata:true "http://169.254.169.254/metadata/instance/compute?api-version=2017-03-01" \
  | jq ".name" \
  | sed 's/.*_//' \
  | sed 's/"//'`

nodeDNS='vm0.node-'$uniqueString'.'$location'.cloudapp.azure.com'

echo Adding neo4j yum repo...
rpm --import https://debian.neo4j.com/neotechnology.gpg.key
echo "
[neo4j]
name=Neo4j Yum Repo
baseurl=http://yum.neo4j.com/stable
enabled=1
gpgcheck=1" > /etc/yum.repos.d/neo4j.repo

echo Writing neo4j license key file...
echo $licenseKey > /etc/neo4j/license/neo4j.license

echo Installing Graph Database...
export NEO4J_ACCEPT_LICENSE_AGREEMENT=yes
yum -y install neo4j-enterprise-${graphDatabaseVersion}

echo Configuring network in neo4j.conf...
sed -i 's/#dbms.default_listen_address=0.0.0.0/dbms.default_listen_address=0.0.0.0/g' /etc/neo4j/neo4j.conf
publicHostname=$(curl -s http://169.254.169.254/latest/meta-data/public-hostname)
sed -i s/#dbms.default_advertised_address=localhost/dbms.default_advertised_address=${publicHostname}/g /etc/neo4j/neo4j.conf

if [[ \"$nodeCount\" == 1 ]]; then
  echo Running on a single node.
else
  echo Running on multiple nodes.  Configuring membership in neo4j.conf...
  region=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/.$//')
  instanceId=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
  stackName=$(aws cloudformation describe-stack-resources --physical-resource-id $instanceId --query 'StackResources[0].StackName' --output text --region $region)
  coreMembers=$(aws autoscaling describe-auto-scaling-instances --region $region --output text --query \"AutoScalingInstances[?AutoScalingGroupName=='Neo4jAutoScalingGroup'].InstanceId\" | xargs -n1 aws ec2 describe-instances --instance-ids $ID --region $region --query \"Reservations[].Instances[].PublicDnsName\" --output text --filter \"Name=tag:aws:cloudformation:stack-name,Values=$stackName\")
  coreMembers=$(echo $coreMembers | sed 's/ /:5000,/g')
  coreMembers=$(echo $coreMembers):5000
  sed -i s/#causal_clustering.initial_discovery_members=localhost:5000,localhost:5001,localhost:5002/causal_clustering.initial_discovery_members=${coreMembers}/g /etc/neo4j/neo4j.conf
  sed -i s/#dbms.mode=CORE/dbms.mode=CORE/g /etc/neo4j/neo4j.conf
fi
            
echo Turning on SSL...
sed -i 's/dbms.connector.https.enabled=false/dbms.connector.https.enabled=true/g' /etc/neo4j/neo4j.conf
#sed -i 's/#dbms.connector.bolt.tls_level=DISABLED/dbms.connector.bolt.tls_level=OPTIONAL/g' /etc/neo4j/neo4j.conf

/etc/pki/tls/certs/make-dummy-cert cert
awk '/-----BEGIN PRIVATE KEY-----/,/-----END PRIVATE KEY-----/' cert > private.key
awk '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/' cert > public.crt

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

if [[ \"$graphDataScienceVersion\" != None ]]; then
  echo Installing Graph Data Science...
  curl \"https://s3-eu-west-1.amazonaws.com/com.neo4j.graphalgorithms.dist/graph-data-science/neo4j-graph-data-science-${graphDataScienceVersion}-standalone.zip\" -o neo4j-graph-data-science-${graphDataScienceVersion}-standalone.zip
  unzip neo4j-graph-data-science-${graphDataScienceVersion}-standalone.zip
  mv neo4j-graph-data-science-${graphDataScienceVersion}.jar /var/lib/neo4j/plugins
fi

if [[ \"$bloomVersion\" != None ]]; then
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
neo4j-admin set-initial-password ${password}