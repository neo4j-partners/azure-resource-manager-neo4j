#!/bin/bash

echo Running startup script...
export password=${1}

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
yum -y install neo4j

echo "Configuring network in neo4j.conf..."
sed -i "s/#server.default_listen_address=0.0.0.0/server.default_listen_address=0.0.0.0/g" /etc/neo4j/neo4j.conf

echo "Starting Neo4j..."
neo4j-admin dbms set-initial-password "$password"
systemctl enable neo4j
/usr/bin/neo4j start
