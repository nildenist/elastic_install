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

# Validate configuration variables
if [ -z "$ELASTIC_VERSION" ] || [ -z "$INSTALL_DIR" ] || [ -z "$CONFIG_DIR" ] || [ -z "$DATA_DIR" ] || [ -z "${SEED_HOSTS[*]}" ]; then
  echo "One or more required environment variables are missing. Please check elastic_config.env."
  exit 1
fi

# Set persistent ulimit for elasticsearch user
echo "Setting ulimit for 'elasticsearch' user to 65535..."

# Check if the limit is already set in /etc/security/limits.conf
if ! grep -q "elasticsearch  -  nofile  65535" /etc/security/limits.conf; then
  echo "Adding ulimit for elasticsearch user to /etc/security/limits.conf..."
  echo "elasticsearch  -  nofile  65535" | sudo tee -a /etc/security/limits.conf > /dev/null
else
  echo "ulimit for elasticsearch user is already set in /etc/security/limits.conf."
fi

# Ensure PAM limits are applied (if needed on your system)
if ! grep -q "session required pam_limits.so" /etc/pam.d/common-session; then
  echo "Ensuring pam_limits.so is configured for session limits..."
  echo "session required pam_limits.so" | sudo tee -a /etc/pam.d/common-session > /dev/null
else
  echo "pam_limits.so is already configured."
fi

# Install and configure Elasticsearch
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

# Create a dedicated user and group for Elasticsearch if not exists
echo "Creating 'elasticsearch' user and group..."
if ! id -u elasticsearch &>/dev/null; then
  sudo groupadd elasticsearch
  sudo useradd -g elasticsearch -s /bin/bash -M -r elasticsearch
else
  echo "'elasticsearch' user and group already exist."
fi

# Ensure the required directories exist
echo "Ensuring required directories exist..."
sudo mkdir -p "$DATA_DIR" "$CONFIG_DIR" "/var/log/elasticsearch"

# Set permissions for Elasticsearch directories
echo "Setting file permissions..."
sudo chown -R elasticsearch:elasticsearch "$INSTALL_DIR"
sudo chown -R elasticsearch:elasticsearch "$DATA_DIR"
sudo chown -R elasticsearch:elasticsearch "$CONFIG_DIR"
sudo chown -R elasticsearch:elasticsearch /var/log/elasticsearch
sudo chmod -R 755 /var/log/elasticsearch

# Check if UFW is installed, and install it if necessary
echo "Checking if ufw is installed..."
if ! command -v ufw &> /dev/null; then
  echo "UFW is not installed. Installing ufw..."
  sudo apt-get update -y
  sudo apt-get install -y ufw
else
  echo "UFW is already installed."
fi

# Update the package index and install prerequisites
echo "Installing additional dependencies..."
sudo apt-get install -y wget curl apt-transport-https openjdk-17-jdk

# Create the final YAML content for Elasticsearch
echo "Creating final YAML configuration for $ROLE node..."

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
    FINAL_YAML+=$(printf '\n  - "%s%b"\n' "$SEED")
  done

fi

# Now that Elasticsearch is installed, copy the final YAML content to CORE_CONFIG_DIR
echo "$FINAL_YAML" | sudo tee "$CORE_CONFIG_DIR" > /dev/null

# Verify the YAML file has been updated
if [ -f "$CORE_CONFIG_DIR" ]; then
  echo "YAML configuration file has been successfully updated in $CORE_CONFIG_DIR."
else
  echo "Failed to update the YAML configuration file."
  exit 1
fi

# Configure firewall to allow Elasticsearch ports (9200 and 9300)
echo "Configuring firewall to allow incoming traffic on ports 9200 and 9300..."
sudo ufw allow 9200:9300/tcp
sudo ufw reload

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
