          - - "#!/bin/bash\n"
            - "echo Running startup script...\n"

            - "graphDatabaseVersion="
            - Ref: GraphDatabaseVersion
            - "\n"

            - "graphDataScienceVersion="
            - Ref: GraphDataScienceVersion
            - "\n"

            - "bloomVersion="
            - Ref: BloomVersion
            - "\n"

            - "password="
            - Ref: Password
            - "\n"

            - "licenseKey="
            - Ref: LicenseKey
            - "\n"

            - "nodeCount="
            - Ref: NodeCount
            - "\n"

            - "echo Adding neo4j yum repo...\n"
            - "rpm --import https://debian.neo4j.com/neotechnology.gpg.key\n"
            - "echo \""
            - "[neo4j]\n"
            - "name=Neo4j Yum Repo\n"
            - "baseurl=http://yum.neo4j.com/stable\n"
            - "enabled=1\n"
            - "gpgcheck=1\" > /etc/yum.repos.d/neo4j.repo\n"

            - "echo Writing neo4j license key file...\n"
            - "echo $licenseKey > /etc/neo4j/license/neo4j.license\n"

            - "echo Installing Graph Database...\n"
            - "export NEO4J_ACCEPT_LICENSE_AGREEMENT=yes\n"
            - "yum -y install neo4j-enterprise-${graphDatabaseVersion}\n"

            - "echo Configuring network in neo4j.conf...\n"
            - "sed -i 's/#dbms.default_listen_address=0.0.0.0/dbms.default_listen_address=0.0.0.0/g' /etc/neo4j/neo4j.conf\n"
            - "publicHostname=$(curl -s http://169.254.169.254/latest/meta-data/public-hostname)\n"
            - "sed -i s/#dbms.default_advertised_address=localhost/dbms.default_advertised_address=${publicHostname}/g /etc/neo4j/neo4j.conf\n"

            - "if [[ \"$nodeCount\" == 1 ]]; then\n"
            - "  echo Running on a single node.\n"
            - "else\n"
            - "  echo Running on multiple nodes.  Configuring membership in neo4j.conf...\n"
            - "  region=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/.$//')\n"
            - "  instanceId=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)\n"
            - "  stackName=$(aws cloudformation describe-stack-resources --physical-resource-id $instanceId --query 'StackResources[0].StackName' --output text --region $region)\n"
            - "  coreMembers=$(aws autoscaling describe-auto-scaling-instances --region $region --output text --query \"AutoScalingInstances[?AutoScalingGroupName=='Neo4jAutoScalingGroup'].InstanceId\" | xargs -n1 aws ec2 describe-instances --instance-ids $ID --region $region --query \"Reservations[].Instances[].PublicDnsName\" --output text --filter \"Name=tag:aws:cloudformation:stack-name,Values=$stackName\")\n"
            - "  coreMembers=$(echo $coreMembers | sed 's/ /:5000,/g')\n"
            - "  coreMembers=$(echo $coreMembers):5000\n"
            - "  sed -i s/#causal_clustering.initial_discovery_members=localhost:5000,localhost:5001,localhost:5002/causal_clustering.initial_discovery_members=${coreMembers}/g /etc/neo4j/neo4j.conf\n"
            - "  sed -i s/#dbms.mode=CORE/dbms.mode=CORE/g /etc/neo4j/neo4j.conf\n"
            - "fi\n"
            
            - "echo Turning on SSL...\n"
            - "sed -i 's/dbms.connector.https.enabled=false/dbms.connector.https.enabled=true/g' /etc/neo4j/neo4j.conf\n"
            - "#sed -i 's/#dbms.connector.bolt.tls_level=DISABLED/dbms.connector.bolt.tls_level=OPTIONAL/g' /etc/neo4j/neo4j.conf\n"

            - "/etc/pki/tls/certs/make-dummy-cert cert\n"
            - "awk '/-----BEGIN PRIVATE KEY-----/,/-----END PRIVATE KEY-----/' cert > private.key\n"
            - "awk '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/' cert > public.crt\n"

            - "#for service in bolt https cluster backup; do\n"
            - "for service in https; do\n"
            - "  sed -i \"s/#dbms.ssl.policy.${service}/dbms.ssl.policy.${service}/g\" /etc/neo4j/neo4j.conf\n"
            - "  mkdir -p /var/lib/neo4j/certificates/${service}/trusted\n"
            - "  mkdir -p /var/lib/neo4j/certificates/${service}/revoked\n"
            - "  cp private.key /var/lib/neo4j/certificates/${service}\n"
            - "  cp public.crt /var/lib/neo4j/certificates/${service}\n"
            - "done\n"

            - "chown -R neo4j:neo4j /var/lib/neo4j/certificates\n"
            - "chmod -R 755 /var/lib/neo4j/certificates\n"

            - "if [[ \"$graphDataScienceVersion\" != None ]]; then\n"
            - "  echo Installing Graph Data Science...\n"
            - "  curl \"https://s3-eu-west-1.amazonaws.com/com.neo4j.graphalgorithms.dist/graph-data-science/neo4j-graph-data-science-${graphDataScienceVersion}-standalone.zip\" -o neo4j-graph-data-science-${graphDataScienceVersion}-standalone.zip\n"
            - "  unzip neo4j-graph-data-science-${graphDataScienceVersion}-standalone.zip\n"
            - "  mv neo4j-graph-data-science-${graphDataScienceVersion}.jar /var/lib/neo4j/plugins\n"
            - "fi\n"

            - "if [[ \"$bloomVersion\" != None ]]; then\n"
            - "  echo Installing Bloom...\n"
            - "  curl -L \"https://neo4j.com/artifact.php?name=neo4j-bloom-${bloomVersion}.zip\" -o neo4j-bloom-${bloomVersion}.zip\n"
            - "  unzip neo4j-bloom-${bloomVersion}.zip\n"
            - "  mv \"bloom-plugin-4.x-${bloomVersion}.jar\" /var/lib/neo4j/plugins\n"
            - "fi\n"

            - "echo Configuring Graph Data Science and Bloom in neo4j.conf...\n"
            - "sed -i s/#dbms.security.procedures.unrestricted=my.extensions.example,my.procedures.*/dbms.security.procedures.unrestricted=gds.*,bloom.*/g /etc/neo4j/neo4j.conf\n"
            - "sed -i s/#dbms.security.procedures.allowlist=apoc.coll.*,apoc.load.*,gds.*/dbms.security.procedures.allowlist=apoc.coll.*,apoc.load.*,gds.*,bloom.*/g /etc/neo4j/neo4j.conf\n"

            - "echo Starting Neo4j...\n"
            - "service neo4j start\n"
            - "neo4j-admin set-initial-password ${password}\n"