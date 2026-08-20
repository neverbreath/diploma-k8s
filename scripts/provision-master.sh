#!/bin/bash
set -e

# The script is run as user admin with sudo privileges.
# If run from Vagrant, the admin user already exists.

echo "=== [Prod-Server] Starting setup ==="

# 1. Disable swap and configure network stack
echo "--- Disabling swap ---"
sudo swapoff -a
sudo sed -i '/swap/d' /etc/fstab
sudo modprobe br_netfilter
echo "net.bridge.bridge-nf-call-iptables = 1" | sudo tee -a /etc/sysctl.d/k8s.conf
echo "net.bridge.bridge-nf-call-ip6tables = 1" | sudo tee -a /etc/sysctl.d/k8s.conf
sudo sysctl --system

# 2. Install required packages
echo "--- Installing Docker and Kubernetes ---"
sudo apt-get update
sudo apt-get install -y docker-engine kubeadm kubelet kubectl crictl

# 3. Start services
echo "--- Starting Docker and kubelet ---"
sudo systemctl enable --now docker
sudo systemctl enable --now kubelet

# 4. Add entry to /etc/hosts
echo "--- Configuring hosts ---"
echo "192.168.100.10 prod-server prod-server.local" | sudo tee -a /etc/hosts

# 5. Initialize Kubernetes cluster
echo "--- Initializing kubeadm ---"
sudo kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address=192.168.100.10

# 6. Copy kubeconfig to admin's home directory
echo "--- Copying kubeconfig ---"
mkdir -p $HOME/.kube
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# 7. Install Flannel network plugin
echo "--- Installing Flannel ---"
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml

# 8. Remove taint from control-plane (for single-node cluster)
echo "--- Removing taint ---"
kubectl taint nodes $(hostname) node-role.kubernetes.io/control-plane:NoSchedule- || true

# 9. Generate self-signed certificate for Docker Registry
echo "--- Creating certificate for registry ---"
sudo mkdir -p /certs
sudo openssl req -newkey rsa:4096 -nodes -sha256 -keyout /certs/registry.key \
  -x509 -days 365 -out /certs/registry.crt -subj "/CN=192.168.100.10"

# 10. Run private Docker Registry with TLS
echo "--- Starting registry ---"
# Requires admin to be in the docker group, otherwise use sudo docker.
# Since we didn't add admin to the docker group in the Vagrantfile, we use sudo.
sudo docker run -d --restart=always --name registry \
  -v /certs:/certs \
  -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/registry.crt \
  -e REGISTRY_HTTP_TLS_KEY=/certs/registry.key \
  -p 5000:5000 registry:2

# 11. Wait for node readiness
echo "--- Waiting for cluster readiness ---"
kubectl wait --for=condition=Ready node --all --timeout=180s

# 12. Apply Kubernetes manifests from /vagrant/kubernetes
echo "--- Applying manifests ---"
sudo chmod -R a+r /vagrant/kubernetes   # so admin can read
kubectl apply -f /vagrant/kubernetes/

# 13. Copy registry certificate to /vagrant/configs for Dev-Workstation
echo "--- Copying certificate to /vagrant/configs ---"
sudo cp /certs/registry.crt /vagrant/configs/registry.crt

echo "=== [Prod-Server] Setup completed ==="
