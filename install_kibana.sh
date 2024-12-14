#!/bin/bash

# Check if kibana_config.env exists
if [ ! -f "kibana_config.env" ]; then
  echo "Error: kibana_config.env file not found in the current directory!"
  exit 1
fi

# Load parameters from kibana_config.env
source kibana_config.env

# Validate required parameters
if [ -z "$KIBANA_VERSION" ] || [ -z "$INSTALL_DIR" ] || [ -z "$CONFIG_DIR" ] || [ -z "$ES_HOST" ]; then
  echo "Error: Missing required parameters in kibana_config.env!"
  exit 1
fi

# Update the package index and install prerequisites
echo "Updating package index and installing prerequisites..."
sudo apt-get update -y
sudo apt-get install -y wget curl apt-transport-https openjdk-17-jdk

# Download and install Kibana
if [ ! -d "$INSTALL_DIR" ]; then
  echo "Downloading and installing Kibana $KIBANA_VERSION..."
  wget https://artifacts.elastic.co/downloads/kibana/kibana-$KIBANA_VERSION-linux-x86_64.tar.gz
  tar -xzf kibana-$KIBANA_VERSION-linux-x86_64.tar.gz
  sudo mv kibana-$KIBANA_VERSION-linux-x86_64 "$INSTALL_DIR"
fi

# Configure Kibana
echo "Configuring Kibana..."
sudo mkdir -p "$CONFIG_DIR"
cat <<EOL | sudo tee "$CONFIG_DIR/kibana.yml"
server.host: "$KIBANA_HOST"
elasticsearch.hosts: ["$ES_HOST"]
elasticsearch.username: "$KIBANA_USER"
elasticsearch.password: "$KIBANA_PASS"
EOL

# Set permissions
echo "Setting permissions for $INSTALL_DIR..."
sudo chown -R $USER:$USER "$INSTALL_DIR"
sudo chmod -R 755 "$INSTALL_DIR"

# Create a systemd service file for Kibana
echo "Creating Kibana systemd service..."
sudo bash -c 'cat <<EOL > /etc/systemd/system/kibana.service
[Unit]
Description=Kibana
After=network.target

[Service]
ExecStart='$INSTALL_DIR'/bin/kibana
Restart=always
User='$USER'
Group='$USER'
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOL'

# Reload systemd and start Kibana
echo "Reloading systemd and starting Kibana..."
sudo systemctl daemon-reload
sudo systemctl enable kibana
sudo systemctl start kibana

# Display status
echo "Kibana installation and configuration completed successfully!"
sudo systemctl status kibana
