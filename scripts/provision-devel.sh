#!/bin/bash
set -e

# The script is run as user developer with sudo privileges.
# User developer is already created in the Vagrantfile.

echo "=== [Dev-Workstation] Starting setup ==="

# 1. Installing Docker
echo "--- Installing Docker ---"
sudo apt-get update
sudo apt-get install -y docker-engine
sudo systemctl enable --now docker

# 2. Adding current user (developer) to the docker group (if not already added)
sudo usermod -aG docker $USER

# 3. Installing kubectl
echo "--- Installing kubectl ---"
sudo apt-get install -y kubectl

# 4. Configuring access to private Docker Registry (certificate)
echo "--- Configuring trust for private registry ---"
sudo mkdir -p /etc/docker/certs.d/192.168.100.10:5000
sudo cp /vagrant/configs/registry.crt /etc/docker/certs.d/192.168.100.10:5000/ca.crt

# 5. Copying kubeconfig to developer's home directory
echo "--- Copying kubeconfig ---"
mkdir -p $HOME/.kube
sudo cp /vagrant/configs/admin.conf $HOME/.kube/config
sudo chown -R $(id -u):$(id -g) $HOME/.kube
# Replacing API server address from 127.0.0.1 to real IP
sed -i 's/127\.0\.0\.1/192.168.100.10/g' $HOME/.kube/config

# 6. Building and publishing images to private registry
echo "--- Building and publishing frontend and backend ---"
# Since docker requires root privileges or membership in the docker group,
# and the current session has not yet reloaded groups (usermod above),
# we could run docker via sudo or start a new su. The simpler approach is
# to use sudo docker for building? However, building as root may create
# files owned by root, which is undesirable. Better to run commands in a
# new su where the docker group is already active. Or restart the session?
# In the script we could do: exec sg docker -c "bash /vagrant/scripts/build_and_push.sh"
# But for simplicity, we assume that the developer user has been added to
# the docker group in the Vagrantfile and a re-login has already occurred
# (after user creation and group addition, we run the main script via
# su - developer, which reloads groups). Therefore we can run docker without sudo.
cd /vagrant/docker/frontend
docker build -t frontend:v1 .
docker tag frontend:v1 192.168.100.10:5000/frontend:v1
docker push 192.168.100.10:5000/frontend:v1

cd /vagrant/docker/backend
docker build -t backend:v1 .
docker tag backend:v1 192.168.100.10:5000/backend:v1
docker push 192.168.100.10:5000/backend:v1

echo "=== [Dev-Workstation] Setup completed ==="
