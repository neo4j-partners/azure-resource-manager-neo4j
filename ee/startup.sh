#!/bin/bash
set -euo pipefail

echo Running startup script...
export password=${1}
export uniqueString=${2}
export location=${3}
export nodeCount=${4}

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
yum -y install neo4j-enterprise

echo "Configuring network in neo4j.conf..."

sed -i 's/#dbms.default_listen_address=0.0.0.0/dbms.default_listen_address=0.0.0.0/g' /etc/neo4j/neo4j.conf
nodeIndex=`curl -H Metadata:true "http://169.254.169.254/metadata/instance/compute?api-version=2017-03-01" \
  | jq ".name" \
  | sed 's/.*_//' \
  | sed 's/"//'`

EXTERNALIP=$(curl -s -H "Metadata: true" "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/publicIpAddress?api-version=2021-02-01&format=text")
echo EXTERNALIP: $EXTERNALIP

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

  #COREMEMBERS=""

  #for ((i=0; i<$nodeCount; i++)); do
  #  NODE_NAME="vm${i}.${uniqueString}.${location}.cloudapp.azure.com"
  #  NODE_IP=$(getent hosts $NODE_NAME | awk '{ print $1 }')
  #  COREMEMBERS+="$NODE_IP:6000,"
  #done

  # Remove trailing comma from the list of core members
  #COREMEMBERS=${COREMEMBERS::-1}
  #echo COREMEMBERS: $COREMEMBERS

  COREMEMBERS="10.0.0.4:6000,10.0.0.5:6000,10.0.0.6:6000"
  sed -i "s/#dbms.cluster.endpoints=localhost:6000,localhost:6001,localhost:6002/dbms.cluster.endpoints=$COREMEMBERS/g" /etc/neo4j/neo4j.conf
fi

echo "Starting Neo4j..."
neo4j-admin dbms set-initial-password "$password"

# The RPM creates this script which does OS checks that incorrectly fail on GC RH platform images.  Neo4j eng is working on a fix.
rm -f /etc/init.d/neo4j

systemctl enable neo4j
service neo4j start
