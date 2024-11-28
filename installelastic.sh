#!/bin/bash

# Load configuration file
if [ -f "elastic_config.env" ]; then
  source elastic_config.env
else
  echo "Configuration file elastic_config.env not found!"
  exit 1
fi

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

# Validate configuration variables
if [ -z "$ELASTIC_VERSION" ] || [ -z "$INSTALL_DIR" ] || [ -z "$CONFIG_DIR" ] || [ -z "$DATA_DIR" ] || [ -z "${SEED_HOSTS[*]}" ]; then
  echo "One or more required environment variables are missing. Please check elastic_config.env."
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
  if [ $? -ne 0 ]; then
    echo "Failed to download Elasticsearch. Exiting."
    exit 1
  fi
  tar -xzf elasticsearch-$ELASTIC_VERSION-linux-x86_64.tar.gz
  sudo mv elasticsearch-$ELASTIC_VERSION "$INSTALL_DIR"
  rm elasticsearch-$ELASTIC_VERSION-linux-x86_64.tar.gz
else
  echo "Elasticsearch is already installed at $INSTALL_DIR."
fi

# Create a dedicated user and group for Elasticsearch
echo "Creating 'elasticsearch' user and group..."
if ! id -u elasticsearch &>/dev/null; then
  sudo groupadd elasticsearch
  sudo useradd -g elasticsearch -s /bin/bash -M -r elasticsearch
else
  echo "'elasticsearch' user and group already exist."
fi

# Ensure proper permissions for installation directory and data directory
echo "Setting file permissions..."
sudo mkdir -p "$DATA_DIR"
sudo mkdir -p "$CONFIG_DIR"
sudo chown -R elasticsearch:elasticsearch "$INSTALL_DIR"
sudo chown -R elasticsearch:elasticsearch "$DATA_DIR"
sudo chown -R elasticsearch:elasticsearch "$CONFIG_DIR"

# Configure Elasticsearch
echo "Configuring Elasticsearch for role: $ROLE, node name: $NODE_NAME..."

# Ensure the YAML file exists
if [ ! -f "$YAML_DIR/$YAML_FILE" ]; then
  echo "Configuration file $YAML_FILE not found in $YAML_DIR!"
  exit 1
fi

# Copy the relevant YAML configuration
sudo cp "$YAML_DIR/$YAML_FILE" "$CONFIG_DIR/elasticsearch.yml"

# Append dynamic settings to the Elasticsearch configuration
echo "Adding dynamic settings to Elasticsearch configuration..."
echo "node.name: $NODE_NAME" | sudo tee -a "$CONFIG_DIR/elasticsearch.yml"
echo "discovery.seed_hosts: [${SEED_HOSTS[*]}]" | sudo tee -a "$CONFIG_DIR/elasticsearch.yml"
exit 1

# Create a systemd service file for Elasticsearch
echo "Creating systemd service..."
sudo bash -c 'cat > /etc/systemd/system/elasticsearch.service << EOF
[Unit]
Description=Elasticsearch
Documentation=https://elastic.co
After=network.target

[Service]
User=elasticsearch
Group=elasticsearch
ExecStart=/opt/elasticsearch/bin/elasticsearch
Restart=always

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

# Final check to ensure Elasticsearch is running
if curl -X GET "http://localhost:9200" &>/dev/null; then
  echo "Elasticsearch is running and accessible."
else
  echo "Elasticsearch service failed to start or is not accessible. Check logs for details."
fi

echo "Elasticsearch installation and configuration complete for role: $ROLE, node name: $NODE_NAME."
