#!/bin/bash

# Define variables
KIBANA_VERSION="7.10.2" # Set the desired Kibana version
INSTALL_DIR="/opt/kibana"
CONFIG_DIR="/etc/kibana"
ES_HOST="http://10.190.102.53:9200" # Set the Elasticsearch host (e.g., the master node)
KIBANA_HOST="0.0.0.0" # Host IP for Kibana to bind to

# Check for sufficient arguments
if [ $# -ne 1 ]; then
  echo "Usage: $0 <kibana-node-id>"
  echo "Example: $0 kibana-1"
  exit 1
fi

NODE_ID=$1
NODE_NAME="kibana-$NODE_ID"

# Update the package index and install prerequisites
echo "Updating package index and installing prerequisites..."
sudo apt-get update -y
sudo apt-get install -y wget curl apt-transport-https openjdk-17-jdk

# Download and install Kibana
if [ ! -d "$INSTALL_DIR" ]; then
  echo "Downloading and installing Kibana $KIBANA_VERSION..."
  wget https://artifacts.elastic.co/downloads/kibana/kibana-$KIBANA_VERSION-linux-x
