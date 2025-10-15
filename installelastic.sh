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


# Validate configuration variables
if [ -z "$ELASTIC_VERSION" ] || [ -z "$INSTALL_DIR" ] || [ -z "$CONFIG_DIR" ] || [ -z "$DATA_DIR" ] || [ -z "${SEED_HOSTS[*]}" ]; then
  echo "One or more required environment variables are missing. Please check elastic_config.env."
  exit 1
fi

# Get node tier from user input (for ILM setup)
if [ "$ROLE" == "data" ]; then
  read -p "What data tier should this node be? (hot/cold) [default: $DEFAULT_NODE_TIER]: " NODE_TIER
  NODE_TIER=${NODE_TIER:-$DEFAULT_NODE_TIER}
  echo "Configuring node as: $NODE_TIER tier"
else
  NODE_TIER="hot"  # Master nodes are typically hot tier
fi


if [ "$ROLE" == "master" ]; then
 # Query if Kibana is going to be installed.
 read -p "Do you want to install Kibana? (y/n): " install_kibana
 if [[ "$install_kibana" =~ ^[yY]$ ]]; then
  # Check if the kibana_config.env file exists
    if [[ -f "kibana_config.env" ]]; then
        echo "kibana_config.env file found. Validating the variables..."

        # Source the kibana_config.env to load the variables
        source kibana_config.env

        # Validate if all required variables are present
        if [[ -z "$KIBANA_VERSION" || -z "$KIBANA_INSTALL_DIR" || -z "$KIBANA_CONFIG_DIR" || -z "$ES_HOST" || -z "$KIBANA_HOST" || -z "$KIBANA_USER" ]]; then
            echo "Error: One or more required variables are missing in kibana_config.env."
            echo "Please ensure the following variables are set: KIBANA_VERSION, KIBANA_INSTALL_DIR, KIBANA_CONFIG_DIR, ES_HOST, KIBANA_HOST, KIBANA_USER."
            exit 1
        else
            echo "kibana_config.env validated successfully."
            echo "Using the following configuration:"
            echo "KIBANA_VERSION=$KIBANA_VERSION"
            echo "KIBANA_INSTALL_DIR=$KIBANA_INSTALL_DIR"
            echo "KIBANA_CONFIG_DIR=$KIBANA_CONFIG_DIR"
            echo "ES_HOST=$ES_HOST"
            echo "KIBANA_HOST=$KIBANA_HOST"
            echo "KIBANA_USER=$KIBANA_USER" 
        fi
    else
        echo "Error: kibana_config.env file not found."
        exit 1
    fi
else
    echo "Skipping Kibana installation."
fi

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

# Set vm.max_map_count permanently
echo "Setting vm.max_map_count to 262144..."

# Check if vm.max_map_count is already set in /etc/sysctl.conf
if ! grep -q "vm.max_map_count=262144" /etc/sysctl.conf; then
  echo "Adding vm.max_map_count=262144 to /etc/sysctl.conf..."
  echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf > /dev/null
else
  echo "vm.max_map_count is already set in /etc/sysctl.conf."
fi

# Reload sysctl configuration to apply the change
sudo sysctl -p

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
  sudo ufw enable
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
node.roles: ["master","data_hot"]
node.attr.data_tier: $NODE_TIER
http.port: 9200
network.host: 0.0.0.0
xpack.security.enabled: true
xpack.security.transport.ssl.enabled: true
xpack.security.transport.ssl.verification_mode: certificate
xpack.security.transport.ssl.client_authentication: required
xpack.security.transport.ssl.keystore.path: elastic-certificates.p12
xpack.security.transport.ssl.truststore.path: elastic-certificates.p12
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
  # Set node roles based on tier
  if [ "$NODE_TIER" == "hot" ]; then
    NODE_ROLES="[\"data_hot\",\"data_content\"]"
  elif [ "$NODE_TIER" == "cold" ]; then
    NODE_ROLES="[\"data_cold\",\"data_content\"]"
  else
    NODE_ROLES="[\"data_content\"]"  # Default data role
  fi
  
  FINAL_YAML=$(cat <<EOF
node.name: $NODE_NAME
node.roles: $NODE_ROLES
node.attr.data_tier: $NODE_TIER
network.host: 0.0.0.0
xpack.security.enabled: true
xpack.security.transport.ssl.enabled: true
xpack.security.transport.ssl.verification_mode: certificate
xpack.security.transport.ssl.client_authentication: required
xpack.security.transport.ssl.keystore.path: elastic-certificates.p12
xpack.security.transport.ssl.truststore.path: elastic-certificates.p12
xpack.security.http.ssl.enabled: false
path.data: /data
path.logs: /var/log/elasticsearch
cluster.name: $CLUSTER_NAME
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
sudo ufw allow 8000
sudo ufw reload
## NEWCODE BLOCK START
if [ "$ROLE" == "master" ]; then
  # Navigate to the Elasticsearch install folder
  cd /opt/elasticsearch
  
  # Generate the CA certificate
  ./bin/elasticsearch-certutil ca

  # Generate the Elasticsearch certificate using the CA
  ./bin/elasticsearch-certutil cert --ca elastic-stack-ca.p12
  
  # Copy the elastic-certificates.p12 file to the config folder
  cp elastic-certificates.p12 config/

  # Start a Python HTTP server to serve the file for temporary use
  echo "Starting Python HTTP server on port 8000..."
  
  # Check if Python3 is installed, and install it if not
  if ! command -v python3 &> /dev/null; then
    echo "Python3 not found, installing it..."
    sudo apt-get update -y
    sudo apt-get install -y python3
  fi
  
 python3 -m http.server 8000 &
SERVER_PID=$!  # Get the process ID of the HTTP server

# Inform the user how to download the file
echo "You can now download the certificate from http://<your-server-ip>:8000/elastic-certificates.p12"
echo "-------------------------"
echo "-------------------------"
echo "-------------------------"
echo "-------------------------"
echo "Temporary web server started. Waiting for clients to download certificate."
echo "-------------------------"
echo "-------------------------"
echo "When all clients downloaded you need to press x to continue next step."
echo "Press 'x' to stop the server and continue."
echo "-------------------------"
echo "-------------------------"
echo "-------------------------" 


# Wait for user input to terminate the server
while true; do
  read -n 1 -s INPUT  # Read a single character without requiring Enter
  if [[ "$INPUT" == "x" ]]; then
    echo -e "\nStopping the server..."
    kill $SERVER_PID  # Terminate the Python HTTP server
    wait $SERVER_PID 2>/dev/null  # Ensure the process is properly cleaned up
    break
  fi
done
  echo "disable temporary port"
  sudo ufw deny 8000
  # Once the server is stopped, the script will continue
  echo "Python HTTP server has been stopped. Continuing with the script..."

  # Add permissions for the elasticsearch user to the certificate file
  echo "Setting permissions for elasticsearch user on elastic-certificates.p12..."
  sudo chown elasticsearch:elasticsearch /opt/elasticsearch/config/elastic-certificates.p12
  sudo chmod 644 /opt/elasticsearch/config/elastic-certificates.p12




fi


if [ "$ROLE" == "data" ]; then
  # Navigate to the /opt/elasticsearch/config folder
  cd /opt/elasticsearch/config
  
  # Get the first seed host from SEED_HOSTS and construct the URL
  SEED_HOST_IP="${SEED_HOSTS[0]}"
  URL="http://$SEED_HOST_IP:8000/elastic-certificates.p12"
  
  # Check if wget is installed, and install it if not
  if ! command -v wget &> /dev/null; then
    echo "wget not found, installing it..."
    sudo apt-get update -y
    sudo apt-get install -y wget
  fi

  # Try to download the elastic-certificates.p12 file with retries
  echo "Attempting to download elastic-certificates.p12 from $URL..."
  RETRIES=0
  MAX_RETRIES=50

  until wget "$URL" -O elastic-certificates.p12; do
    if [ $RETRIES -ge $MAX_RETRIES ]; then
      echo "Failed to download elastic-certificates.p12 after $MAX_RETRIES attempts. Exiting."
      exit 1
    fi
    echo "Download failed, retrying... ($((RETRIES+1))/$MAX_RETRIES)"
    ((RETRIES++))
    sleep 5
  done

  # Once the file is downloaded, set permissions for elasticsearch user
  echo "Setting permissions for elasticsearch user on elastic-certificates.p12..."
  sudo chown elasticsearch:elasticsearch elastic-certificates.p12
  sudo chmod 644 elastic-certificates.p12

fi


## NEWCODE BLOCK END

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



if [ "$ROLE" == "master" ]; then



echo "Waiting for Elasticsearch to initialize..."
# Wait for Elasticsearch to be available on port 9200
RETRY_COUNT=0
MAX_RETRIES=30
while ! curl -s http://localhost:9200 >/dev/null; do
  echo -n "."
  sleep 2
  ((RETRY_COUNT++))
  if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
    echo -e "\nError: Elasticsearch service did not start within the expected time."
    exit 1
  fi
done

echo -e "\nElasticsearch is running."

# Wait 10 seconds before proceeding with password setup
echo -n "Preparing for password setup"
for i in {1..10}; do
  echo -n "."
  sleep 1
done
echo ""

# Run built-in password setup
read -p "Would you like to create built-in passwords now? (y/N): " USER_CHOICE

if [[ "$USER_CHOICE" =~ ^[yY]$ ]]; then
  echo "Running built-in password setup..."
  cd /opt/elasticsearch/bin/
  ./elasticsearch-setup-passwords interactive
  if [[ $? -eq 0 ]]; then
    echo "Built-in passwords created successfully."
  else
    echo "Error occurred during built-in password setup."
    exit 1
  fi
else
  echo "Skipping built-in password creation."
  echo "run /opt/elasticsearch/bin//elasticsearch-setup-passwords interactive"
  echo "to generate built-in passwords"
fi

# Setup Index Lifecycle Management (ILM)
echo ""
read -p "Would you like to configure Index Lifecycle Management (ILM) now? (Y/n): " ILM_CHOICE
ILM_CHOICE=${ILM_CHOICE:-Y}

if [[ "$ILM_CHOICE" =~ ^[yY]$ ]]; then
  echo "Setting up Index Lifecycle Management..."
  run_ilm_setup
  if [[ $? -eq 0 ]]; then
    echo "ILM setup completed successfully."
  else
    echo "Error occurred during ILM setup. You can run it manually later."
    echo "Manual setup instructions:"
    echo "1. Ensure cluster is healthy: curl localhost:9200/_cluster/health"
    echo "2. Run the ILM functions from this script manually"
  fi
else
  echo "Skipping ILM setup."
  echo "You can configure ILM later using the functions in this script."
  echo "ILM Configuration Summary:"
  echo "• Hot tier: $ILM_HOT_DAYS days"
  echo "• Cold tier: $ILM_COLD_DAYS days" 
  echo "• Delete: $ILM_DELETE_DAYS days"
fi

# Functions for ILM setup
setup_ilm_policy() {
  echo "Creating ILM policy: $ILM_POLICY_NAME"
  
  # Create the ILM policy
  curl -X PUT "localhost:9200/_ilm/policy/$ILM_POLICY_NAME" -H 'Content-Type: application/json' -d'
  {
    "policy": {
      "phases": {
        "hot": {
          "min_age": "0ms",
          "actions": {
            "rollover": {
              "max_primary_shard_size": "50gb",
              "max_age": "'$ILM_HOT_DAYS'd"
            },
            "set_priority": {
              "priority": 100
            }
          }
        },
        "cold": {
          "min_age": "'$ILM_COLD_DAYS'd",
          "actions": {
            "set_priority": {
              "priority": 0
            },
            "allocate": {
              "number_of_replicas": 0,
              "include": {
                "data_tier": "cold"
              }
            }
          }
        },
        "delete": {
          "min_age": "'$ILM_DELETE_DAYS'd",
          "actions": {
            "delete": {}
          }
        }
      }
    }
  }'
  
  if [ $? -eq 0 ]; then
    echo "✓ ILM policy '$ILM_POLICY_NAME' created successfully"
  else
    echo "✗ Failed to create ILM policy"
    return 1
  fi
}

setup_index_templates() {
  echo "Creating index templates for automatic ILM policy application"
  
  # Create template for logs
  curl -X PUT "localhost:9200/_index_template/logs-template" -H 'Content-Type: application/json' -d'
  {
    "index_patterns": ["logs-*"],
    "template": {
      "settings": {
        "number_of_shards": 1,
        "number_of_replicas": 1,
        "index.lifecycle.name": "'$ILM_POLICY_NAME'",
        "index.lifecycle.rollover_alias": "logs"
      }
    },
    "priority": 500,
    "version": 1,
    "_meta": {
      "description": "Template for log indices with ILM policy"
    }
  }'
  
  if [ $? -eq 0 ]; then
    echo "✓ Index template for logs created successfully"
  else
    echo "✗ Failed to create index template for logs"
    return 1
  fi
  
  # Create initial index with alias
  curl -X PUT "localhost:9200/logs-000001" -H 'Content-Type: application/json' -d'
  {
    "aliases": {
      "logs": {
        "is_write_index": true
      }
    }
  }'
  
  if [ $? -eq 0 ]; then
    echo "✓ Initial logs index created with alias"
  else
    echo "✗ Failed to create initial logs index"
    return 1
  fi
}

setup_cluster_settings() {
  echo "Configuring cluster settings for ILM and disk management"
  
  # Set disk watermark settings
  curl -X PUT "localhost:9200/_cluster/settings" -H 'Content-Type: application/json' -d'
  {
    "persistent": {
      "cluster.routing.allocation.disk.watermark.low": "'$DISK_WATERMARK_LOW'",
      "cluster.routing.allocation.disk.watermark.high": "'$DISK_WATERMARK_HIGH'",
      "cluster.routing.allocation.disk.watermark.flood_stage": "'$DISK_WATERMARK_FLOOD'",
      "cluster.routing.allocation.disk.include_relocations": true,
      "indices.lifecycle.poll_interval": "1m",
      "cluster.routing.allocation.awareness.attributes": "data_tier"
    }
  }'
  
  if [ $? -eq 0 ]; then
    echo "✓ Cluster settings configured successfully"
  else
    echo "✗ Failed to configure cluster settings"
    return 1
  fi
}

run_ilm_setup() {
  echo "=== Starting Index Lifecycle Management Setup ==="
  
  # Wait for cluster to be ready
  echo "Waiting for cluster to be ready..."
  local retries=0
  local max_retries=30
  
  while ! curl -s "localhost:9200/_cluster/health?wait_for_status=yellow&timeout=5s" > /dev/null; do
    sleep 2
    ((retries++))
    if [ $retries -ge $max_retries ]; then
      echo "✗ Cluster not ready after $max_retries attempts"
      return 1
    fi
    echo -n "."
  done
  echo ""
  echo "✓ Cluster is ready"
  
  # Setup ILM components
  setup_cluster_settings
  if [ $? -ne 0 ]; then return 1; fi
  
  setup_ilm_policy
  if [ $? -ne 0 ]; then return 1; fi
  
  setup_index_templates
  if [ $? -ne 0 ]; then return 1; fi
  
  echo "=== ILM Setup Complete ==="
  echo ""
  echo "Your Elasticsearch cluster is now configured with:"
  echo "• Hot data tier: Keeps data for $ILM_HOT_DAYS days"
  echo "• Cold data tier: Archives data from day $ILM_HOT_DAYS to day $ILM_COLD_DAYS"
  echo "• Deletion: Removes data after $ILM_DELETE_DAYS days"
  echo "• Disk watermarks: Low=$DISK_WATERMARK_LOW, High=$DISK_WATERMARK_HIGH, Flood=$DISK_WATERMARK_FLOOD"
  echo ""
  echo "To use the ILM policy, index your logs to: 'logs' alias"
  echo "Example: curl -X POST 'localhost:9200/logs/_doc' -H 'Content-Type: application/json' -d '{\"message\":\"test log\"}'"
}

echo "Script execution completed."

fi



# Proceed to Kibana installation section, after ensuring we are on the master node
if [ "$ROLE" == "master" ]; then

if [[ "$install_kibana" =~ ^[yY]$ ]]; then
    echo "Starting Kibana installation process..."

    # Prompt for Kibana password if not already set
    
        read -sp "Please enter the Kibana password: " KIBANA_PASS
        echo  # For newline after password input
    
    if ! id -u kibana > /dev/null 2>&1; then
        echo "Creating Kibana user and group..."
        sudo groupadd kibana
        sudo useradd -g kibana -s /bin/bash -d $KIBANA_INSTALL_DIR kibana
    fi

    
    # Install Kibana (using the version defined in the environment file)
    echo "Installing Kibana version $KIBANA_VERSION..."
    wget https://artifacts.elastic.co/downloads/kibana/kibana-$KIBANA_VERSION-linux-x86_64.tar.gz
    tar -xvzf kibana-$KIBANA_VERSION-linux-x86_64.tar.gz
    mv kibana-$KIBANA_VERSION $KIBANA_INSTALL_DIR
      
      
      sudo chown -R kibana:kibana /opt/kibana/data
      sudo chmod -R 775 /opt/kibana/data


    # Update the Kibana configuration (kibana.yml)
    echo "Configuring Kibana..."
    if [[ -f "$KIBANA_CONFIG_DIR/kibana.yml" ]]; then
        # Modify Kibana configuration file (kibana.yml)
         
        echo "server.host: \"$KIBANA_HOST\"" >> "$KIBANA_CONFIG_DIR/kibana.yml"
        echo "elasticsearch.username: \"$KIBANA_USER\"" >> "$KIBANA_CONFIG_DIR/kibana.yml"
        echo "elasticsearch.password: $KIBANA_PASS" >> "$KIBANA_CONFIG_DIR/kibana.yml"
    else
        echo "Error: Kibana configuration file not found at $KIBANA_CONFIG_DIR/kibana.yml."
        exit 1
    fi
  
    # Configure firewall settings for Kibana
    echo "Configuring firewall for Kibana..."
    sudo ufw allow 5601/tcp
    sudo ufw allow 5601
    sudo ufw reload
    

    # Set up Kibana service (assuming systemd)
    echo "Creating Kibana service..."
    cat > /etc/systemd/system/kibana.service <<EOF
[Unit]
Description=Kibana
After=network.target

[Service]
ExecStart=$KIBANA_INSTALL_DIR/bin/kibana
Restart=always
User=kibana
Group=kibana

[Install]
WantedBy=multi-user.target
EOF

    # Start and enable the Kibana service
    echo "Starting Kibana service..."
    systemctl daemon-reload
    systemctl enable kibana
    systemctl start kibana

    echo "Kibana installation and setup completed successfully."
fi

fi
