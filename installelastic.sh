#!/bin/bash

# Define variables
ELASTIC_VERSION="7.10.2" # Set the desired Elasticsearch version
INSTALL_DIR="/opt/elasticsearch"
CONFIG_DIR="/etc/elasticsearch"
DATA_DIR="/data"
SEED_HOSTS=("10.190.102.53" "10.190.102.54" "10.190.102.55") # List of all master-eligible node IPs

# Check for sufficient arguments
if [ $# -ne 3 ]; then
  echo "Usage: $0 <type: master|data> <cluster-name> <node-id>"
  echo "Example: $0 master my-cluster 1"
  exit 1
fi

ROLE=$1
CLUSTER_NAME=$2
NODE_ID=$3

# Define naming convention
if [ "$ROLE" == "master" ]; then
  NODE_NAME="master-$NODE_ID"
elif [ "$ROLE" == "data" ]; then
  NODE_NAME="data-$NODE_ID"
else
  echo "Invalid type: $ROLE. Use 'master' or 'data'."
  exit 1
fi

# Update the package index and install prerequisites
echo "Updating package index and installing prerequisites..."
sudo apt-get update -y
sudo apt-get install -y wget curl apt-transport-https openjdk-17-jdk

# Download and install Elasticsearch
if [ ! -d "$INSTALL_DIR" ]; then
  echo "Downloading and installing Elasticsearch $ELASTIC_VERSION..."
  wget https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-$ELASTIC_VERSION-linux-x86_64.tar.gz
  tar -xzf elasticsearch-$ELASTIC_VERSION-linux-x86_64.tar.gz
  sudo mv elasticsearch-$ELASTIC_VERSION $INSTALL_DIR
  rm elasticsearch-$ELASTIC_VERSION-linux-x86_64.tar.gz
else
  echo "Elasticsearch is already installed at $INSTALL_DIR."
fi

# Configure Elasticsearch
echo "Configuring Elasticsearch for role: $ROLE, cluster: $CLUSTER_NAME, node name: $NODE_NAME..."
sudo mkdir -p $CONFIG_DIR
sudo mkdir -p $DATA_DIR

# Set permissions for /data
echo "Setting permissions for $DATA_DIR..."
sudo chown -R root:root $DATA_DIR
sudo chmod -R 775 $DATA_DIR

# Create the elasticsearch.yml configuration dynamically
sudo bash -c "cat > $CONFIG_DIR/elasticsearch.yml << EOF
cluster.name: $CLUSTER_NAME
node.name: $NODE_NAME
EOF"

if [ "$ROLE" == "master" ]; then
  sudo bash -c "cat >> $CONFIG_DIR/elasticsearch.yml << EOF
node.master: true
node.data: false
EOF"
elif [ "$ROLE" == "data" ]; then
  sudo bash -c "cat >> $CONFIG_DIR/elasticsearch.yml << EOF
node.master: true
node.data: true
EOF"
fi

# Common settings for all nodes
sudo bash -c "cat >> $CONFIG_DIR/elasticsearch.yml << EOF
network.host: 0.0.0.0
discovery.seed_hosts: [\"${SEED_HOSTS[*]}\"] # Master-eligible node IPs
path.data: $DATA_DIR
EOF"

if [ "$ROLE" == "master" ]; then
  sudo bash -c "cat >> $CONFIG_DIR/elasticsearch.yml << EOF
cluster.initial_master_nodes: [\"master-1\", \"master-2\", \"master-3\"] # Predictable master names
EOF"
fi

sudo bash -c "cat >> $CONFIG_DIR/elasticsearch.yml << EOF
path.logs: /var/log/elasticsearch
EOF"

# Create a systemd service file for Elasticsearch
echo "Creating systemd service..."
sudo bash -c 'cat > /etc/systemd/system/elasticsearch.service << EOF
[Unit]
Description=Elasticsearch
Documentation=https://elastic.co
Wants=network-online.target
After=network-online.target

[Service]
Type=notify
ExecStart=/opt/elasticsearch/bin/elasticsearch
Restart=on-failure
User=root
Group=root
LimitNOFILE=65536
LimitMEMLOCK=infinity

[Install]
WantedBy=multi-user.target
EOF'

# Enable and start the service
echo "Starting Elasticsearch service..."
sudo systemctl daemon-reload
sudo systemctl enable elasticsearch
sudo systemctl start elasticsearch

# Verify the service
echo "Verifying Elasticsearch status..."
sudo systemctl status elasticsearch --no-pager

echo "Elasticsearch installation and configuration complete for role: $ROLE, cluster: $CLUSTER_NAME, node name: $NODE_NAME, data directory: $DATA_DIR."
