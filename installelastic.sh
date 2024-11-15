#!/bin/bash

# Define variables
ELASTIC_VERSION="7.10.2" # Set the desired Elasticsearch version
INSTALL_DIR="/opt/elasticsearch"
CONFIG_DIR="/etc/elasticsearch"
DATA_DIR="/data"
SEED_HOSTS=("10.190.102.53" "10.190.102.54" "10.190.102.55") # List of all master-eligible node IPs
YAML_DIR="./" # Directory where the YAML files are located (same directory as the script)
 
# Check for sufficient arguments
if [ $# -ne 2 ]; then
  echo "Usage: $0 <type: master|data> <node-id>"
  echo "Example: $0 master 1"
  exit 1
fi

ROLE=$1
NODE_ID=$2
NODE_NAME=""

# Select YAML based on role
if [ "$ROLE" == "master" ]; then
  YAML_FILE="master.yaml"
  NODE_NAME="master-$NODE_ID"
elif [ "$ROLE" == "data" ]; then
  YAML_FILE="data.yaml"
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
echo "Configuring Elasticsearch for role: $ROLE, node name: $NODE_NAME..."

# Ensure the YAML file exists
if [ ! -f "$YAML_DIR/$YAML_FILE" ]; then
  echo "Configuration file $YAML_FILE not found in $YAML_DIR!"
  exit 1
fi

# Copy the relevant YAML configuration
sudo mkdir -p $CONFIG_DIR
sudo cp "$YAML_DIR/$YAML_FILE" "$CONFIG_DIR/elasticsearch.yml"

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

echo "Elasticsearch installation and configuration complete for role: $ROLE, node name: $NODE_NAME."
