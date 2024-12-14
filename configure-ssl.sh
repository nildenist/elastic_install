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
 
cd $INSTALL_DIR
cd bin

./elasticsearch-certutil ca
