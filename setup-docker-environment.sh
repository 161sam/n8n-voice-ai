#!/bin/bash
# setup-docker-environment.sh

# Update system
sudo apt update && sudo apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Install NVIDIA Container Toolkit (if GPU enabled)
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | sudo tee /etc/apt/sources.list.d/nvidia-docker.list
sudo apt-get update && sudo apt-get install -y nvidia-docker2
sudo systemctl restart docker

# Create directory structure
sudo mkdir -p /opt/n8n-voice-ai/{data,config,logs,backups}
sudo chown -R $USER:$USER /opt/n8n-voice-ai

# Install monitoring tools
sudo apt install -y htop iotop nethogs

# Configure firewall
sudo ufw allow 22      # SSH
sudo ufw allow 80      # HTTP
sudo ufw allow 443     # HTTPS
sudo ufw allow 5678    # n8n
sudo ufw --force enable

echo "Docker environment setup complete!"
echo "Next steps:"
echo "1. Copy docker-compose.yml to /opt/n8n-voice-ai/"
echo "2. Copy .env file to /opt/n8n-voice-ai/"
echo "3. Run: cd /opt/n8n-voice-ai && docker-compose up -d"
