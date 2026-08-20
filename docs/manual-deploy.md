# Manual Deployment of the Lab Environment

This guide provides step-by-step instructions for manual deployment of a laboratory environment that simulates a container management system based on Docker and Kubernetes, fully replicating the process described in the thesis. All actions are performed manually on three virtual machines running Alt Linux OS.

## Prerequisites

Three virtual machines (VirtualBox, VMware or similar) with the following parameters:

| Machine          | OS                | Hostname        | IP        | User |
|-----------------|-------------------|-----------------|-----------------|--------------|
| Prod-Server     | Alt Server 10.4   | prod-server     | 192.168.100.10  | admin        |
| Dev-Workstation | Alt Workstation 10.4 | dev-workstation | 192.168.100.20  | developer    |
| Client          | Alt Workstation 10.4 | client         | 192.168.100.30  | user         |

All machines are in the same local network 192.168.100.0/24. Each machine must have Internet access. If using Cloudflare WARP, it must be activated (see section "Cloudflare WARP" below). All operations requiring privileges are performed via sudo from a regular user (not root).

## Cloudflare WARP

If direct access to Docker Hub and Kubernetes resources is blocked, install Cloudflare WARP.

## Preparation of Prod-Server (Kubernetes control plane node)

### 1.1. Disable swap and configure network stack

```bash
sudo swapoff -a

sudo sed -i '/swap/s/^/#/' /etc/fstab

sudo modprobe br_netfilter

cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

sudo sysctl --system
```

### 1.2. Install Docker

```bash
sudo apt-get update
sudo apt-get install -y docker-engine

sudo systemctl enable --now docker

sudo systemctl status docker
```

### 1.3. Install Kubernetes components

```bash
sudo apt-get install -y kubeadm kubelet kubectl crictl

sudo systemctl enable --now kubelet
```

### 1.4. Configure /etc/hosts

Add an entry associating the hostname with the real IP address (not 127.0.0.1):

```bash
echo "192.168.100.10 prod-server prod-server.local" | sudo tee -a /etc/hosts
```

Verify with:

```bash
hostname -i
```

It should return 192.168.100.10.

### 1.5. Initialize the Kubernetes cluster

```bash
sudo kubeadm init \
  --pod-network-cidr=10.244.0.0/16 \
  --apiserver-advertise-address=192.168.100.10
```

Wait for completion. The output will include a command to join worker nodes (not used in our case).

### 1.6. Copy kubectl configuration

```bash
mkdir -p $HOME/.kube
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

### 1.7. Install Flannel network plugin

```bash
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
```

### 1.8. Remove taint from control-plane (for single-node cluster)

```bash
kubectl taint nodes --all node-role.kubernetes.io/control-plane:NoSchedule-
```

### 1.9. Verify cluster status

```bash
kubectl get nodes
kubectl get pods -n kube-system
```

All pods should become **Running**, and the node should be **Ready**.

## 2. Deploy a private Docker Registry with TLS

### 2.1. Generate a self-signed certificate

```bash
sudo mkdir -p /certs
sudo openssl req -newkey rsa:4096 -nodes -sha256 \
  -keyout /certs/registry.key \
  -x509 -days 365 \
  -out /certs/registry.crt \
  -subj "/CN=192.168.100.10"
```

### 2.2. Run the Registry container

```bash
sudo docker run -d \
  --restart=always \
  --name registry \
  -v /certs:/certs \
  -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/registry.crt \
  -e REGISTRY_HTTP_TLS_KEY=/certs/registry.key \
  -p 5000:5000 \
  registry:2
```

### 2.3. Verify the Registry

```bash
sudo docker ps
curl -k https://192.168.100.10:5000/v2/_catalog
```

Expected response: {"repositories":[]}.

## 3. Configure Dev-Workstation

### 3.1. Install Docker

```bash
sudo apt-get update
sudo apt-get install -y docker-engine
sudo systemctl enable --now docker
```

### 3.2. Add user developer to docker group

```bash
sudo usermod -aG docker $USER
```

**Important:** log out and log back in for changes to take effect.

### 3.3. Add user developer to docker group

Copy the certificate from Prod-Server (using scp or a shared folder). Example with scp:

```bash
mkdir -p /tmp/certs
scp admin@192.168.100.10:/certs/registry.crt /tmp/certs/
sudo mkdir -p /etc/docker/certs.d/192.168.100.10:5000
sudo cp /tmp/certs/registry.crt /etc/docker/certs.d/192.168.100.10:5000/ca.crt
```

### 3.4. Set up SSH access to Prod-Server (optional, for file transfer)

```bash
ssh-keygen -t ed25519
ssh-copy-id admin@192.168.100.10
```

### 3.5. Build Docker images

Create the directory structure and application files (if not already created):

```bash
mkdir -p ~/frontend/html ~/backend
```

**Frontend**: ~/frontend/Dockerfile

```dockerfile
FROM nginx:alpine
LABEL author="developer"
COPY html/index.html /usr/share/nginx/html/index.html
```

**Frontend**: ~/frontend/html/index.html

```html
<!DOCTYPE html>
<html>
<head><title>Frontend Container</title></head>
<body>
<h1>Hello from Frontend Container</h1>
</body>
</html>
```

**Backend**: ~/backend/Dockerfile

```dockerfile
FROM python:3.9-alpine
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
EXPOSE 5000
CMD ["python", "app.py"]
```

**Backend**: ~/backend/requirements.txt

```text
Flask==2.2.2
```

**Backend**: ~/backend/app.py

```python
from flask import Flask, jsonify
import socket

app = Flask(__name__)

@app.route('/')
def hello():
    return jsonify(message="Hello from Backend API!", host=socket.gethostname())

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
```

Build the images:

```bash
cd ~/frontend
docker build -t frontend:v1 .
cd ~/backend
docker build -t backend:v1 .
```

### 3.6. Publish images to the private registry

```bash
docker tag frontend:v1 192.168.100.10:5000/frontend:v1
docker tag backend:v1 192.168.100.10:5000/backend:v1

docker push 192.168.100.10:5000/frontend:v1
docker push 192.168.100.10:5000/backend:v1
```

### 3.7. Install kubectl and configure access to the cluster

```bash
sudo apt-get install -y kubectl
```

Copy admin.conf from Prod-Server:

```bash
mkdir -p ~/.kube
scp admin@192.168.100.10:/etc/kubernetes/admin.conf ~/.kube/config
sed -i 's/127\.0\.0\.1/192.168.100.10/g' ~/.kube/config
chmod 600 ~/.kube/config
```

Verify:

```bash
kubectl get nodes
```

## 4. Deploy applications

### 4.1. Create Kubernetes manifests

On Dev-Workstation, create a directory ~/manifests and the following files:

**namespace.yaml:**

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: app
frontend-deployment.yaml
yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
      - name: frontend
        image: 192.168.100.10:5000/frontend:v1
        ports:
        - containerPort: 80
        imagePullPolicy: Always
```

**frontend-svc.yaml:**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: frontend
  namespace: app
spec:
  type: NodePort
  selector:
    app: frontend
  ports:
  - port: 80
    targetPort: 80
    nodePort: 30080
```

**backend-deployment.yaml:**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
  namespace: app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
    spec:
      containers:
      - name: backend
        image: 192.168.100.10:5000/backend:v1
        ports:
        - containerPort: 5000
        imagePullPolicy: Always
```

**backend-svc.yaml:**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: backend
  namespace: app
spec:
  type: NodePort
  selector:
    app: backend
  ports:
  - port: 5000
    targetPort: 5000
    nodePort: 30500
```

### 4.2. Apply the manifests

```bash
cd ~/manifests
kubectl apply -f namespace.yaml
kubectl apply -f frontend-deployment.yaml -f frontend-svc.yaml -f backend-deployment.yaml -f backend-svc.yaml
```

### 4.3. Verify

```bash
kubectl get pods -n app
kubectl get svc -n app
```

Pods should be in Running state.

### 4.4. Scaling (demonstration)


```bash
kubectl scale deployment frontend --replicas=4 -n app
kubectl get pods -n app
```

## 5. Security configuration

### 5.1. Run a container with restricted privileges (Docker)

```bash
docker run --rm -it --read-only --cap-drop=ALL alpine sh
```

**Attempting to write to root will produce an error: Read-only file system**

### 5.2. Enable Docker Content Trust (optional)

```bash
export DOCKER_CONTENT_TRUST=1
```

To sign images, you will need to configure keys (see Docker documentation).

### 5.3. Install and run Trivy

```bash
sudo apt-get install -y wget
wget https://github.com/aquasecurity/trivy/releases/download/v0.50.0/trivy_0.50.0_Linux-64bit.tar.gz
tar zxvf trivy_0.50.0_Linux-64bit.tar.gz
sudo mv trivy /usr/local/bin/

trivy image 192.168.100.10:5000/frontend:v1
```

### 5.4. Create RBAC policies

**dev-role.yaml:**

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: app
  name: pod-manager
rules:
- apiGroups: [""]
  resources: ["pods", "pods/log"]
  verbs: ["get", "list", "create", "update", "delete"]
dev-rolebinding.yaml
yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: dev-pod-manager
  namespace: app
subjects:
- kind: ServiceAccount
  name: developer
  namespace: app
roleRef:
  kind: Role
  name: pod-manager
  apiGroup: rbac.authorization.k8s.io
```

Create the ServiceAccount:

```bash
kubectl create serviceaccount developer -n app
kubectl apply -f dev-role.yaml -f dev-rolebinding.yaml
```

Get the token for the service account:

```bash
kubectl create token developer -n app
```

### 5.5. Network policy

**network-policy.yaml:**

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-allow-frontend
  namespace: app
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend
    ports:
    - protocol: TCP
      port: 5000
```

```bash
kubectl apply -f network-policy.yaml
```

### 5.6. Apply Pod Security Standards

```bash
kubectl label namespace app \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/audit=restricted \
  pod-security.kubernetes.io/warn=restricted
```

Now all new pods in the app namespace must comply with the restricted profile (no privileges, no root, etc.). Existing pods will not be automatically changed.

## 6. Install Kubernetes Dashboard

### 6.1. Install the dashboard

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml
```

### 6.2. Create an administrative user

Create file **dashboard-admin.yaml:**

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kubernetes-dashboard
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kubernetes-dashboard
```

Apply:

```bash
kubectl apply -f dashboard-admin.yaml
```

### 6.3. Obtain a login token

```bash
kubectl -n kubernetes-dashboard create token admin-user
```

### 6.4. Access the dashboard

On Dev-Workstation, run:

```bash
kubectl proxy &
```

Open in browser:

```text
http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/
```

Paste the token when it is required.

## 7. Verify service availability from the Client machine

On the Client machine (Alt Workstation), simply open a browser or use curl:

```bash
# Check frontend
curl http://192.168.100.10:30080
# Expected HTML with "Hello from Frontend Container"

# Check backend
curl http://192.168.100.10:30500
# Expected JSON: {"message":"Hello from Backend API!", "host":"..."}
```

In a GUI browser, these addresses should also open.

