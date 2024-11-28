#!/bin/bash
# Author: Ozgur SALGINCI
# Load configuration file
if [ -f "elastic_config.env" ]; then
  source elastic_config.env
else
  echo "Configuration file elastic_config.env not found!"
  exit 1
fi

# Check for sufficient arguments
if [ $# -ne 3 ]; then
  echo "Usage: $0 <cluster-name> <role: master|data> <node-name>"
  echo "Example: $0 my-cluster master master-1"
  exit 1
fi

CLUSTER_NAME=$1
ROLE=$2
NODE_NAME=$3

# Select YAML based on role
if [ "$ROLE" == "master" ]; then
  YAML_FILE="master_node.yaml"
elif [ "$ROLE" == "data" ]; then
  YAML_FILE="datanode.yaml"
else
  echo "Invalid role: $ROLE. Use 'master' or 'data'."
  exit 1
fi
     
# Start with the template (either master or data YAML file)
if [ "$ROLE" == "master" ]; then
  FINAL_YAML=$(cat <<EOF
node.name: $NODE_NAME
node.roles: ["master"]
http.port: 9200
network.host: 0.0.0.0
xpack.security.enabled: false
xpack.security.transport.ssl.enabled: false
xpack.security.http.ssl.enabled: false
path.data: /data
path.logs: /var/log/elasticsearch
cluster.name: $CLUSTER_NAME
cluster.initial_master_nodes:
  - "$NODE_NAME"
discovery.seed_hosts:
EOF
)

  
  # Add seed hosts with proper indentation under discovery.seed_hosts
  for SEED in "${SEED_HOSTS[@]}"; do
    FINAL_YAML+=$(printf '\n  - "%s%b"\n' "$SEED")
  done


elif [ "$ROLE" == "data" ]; then
  FINAL_YAML=$(cat <<EOF
node.name: $NODE_NAME
node.roles: ["data"]
network.host: 0.0.0.0
xpack.security.enabled: false
xpack.security.transport.ssl.enabled: false
xpack.security.http.ssl.enabled: false
path.data: /data
path.logs: /var/log/elasticsearch
discovery.seed_hosts:
EOF
)

   # Add seed hosts with proper indentation under discovery.seed_hosts
  for SEED in "${SEED_HOSTS[@]}"; do
    FINAL_YAML+=$(printf '  - "%s"\n' "$SEED")
  done

fi

# Now that Elasticsearch is installed, copy the final YAML content to CORE_CONFIG_DIR
echo "$FINAL_YAML" | sudo tee "test.yml" > /dev/null
