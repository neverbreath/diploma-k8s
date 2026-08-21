# Diploma Project: Container Management System Based on Docker and Kubernetes

This repository contains the complete set of configurations, scripts, and documentation for automatically deploying a laboratory environment that simulates an industrial containerization infrastructure. The environment consists of three virtual machines based on the domestic **Alt Linux 10.4** (Server and Workstation) operating system. Docker, Kubernetes, a private image registry, and a test microservice application are deployed on these machines.

The entire infrastructure is described as code (Infrastructure as Code) using **Vagrant** and shell scripts, allowing the environment to be reproduced with a single command.

## Environment Composition

| Virtual Machine | OS                   | IP Address      | Role                                                                |
|-----------------|----------------------|-----------------|---------------------------------------------------------------------|
| prod-server     | Alt Server 10.4      | 192.168.100.10  | Kubernetes control-plane node, private Docker Registry              |
| dev-workstation | Alt Workstation 10.4 | 192.168.100.20  | Developer workstation: Docker, kubectl, image build and push        |
| client          | Alt Workstation 10.4 | 192.168.100.30  | Client machine for service availability verification                |

The test application consists of two components:
- **Frontend** – Nginx serving a static HTML page.
- **Backend** – Flask application returning JSON.

Both components are built into Docker images, published to a private registry on `prod-server`, and then deployed to Kubernetes using Deployment and Service (NodePort). Security measures include RBAC, NetworkPolicy, Pod Security Standards, capability restrictions, and optional vulnerability scanning.

## Host System Requirements

- **Operating System:** Linux, macOS, or Windows with the following installed:
  - [Vagrant](https://www.vagrantup.com/) (>= 2.2)
  - [VirtualBox](https://www.virtualbox.org/) (>= 6.1) or another supported provider (libvirt)
- **Resources:** at least 8 GB of RAM, 20 GB of free disk space.
- **Internet access:** required to download Alt Linux packages, Docker images, and Kubernetes components. Due to possible restrictions in the Russian Federation, it is recommended to activate **Cloudflare WARP** on the host or configure a proxy server.
- **Privileges:** the user running Vagrant must have permissions to create virtual machines.

## Quick Start

1. **Clone the repository:**

```bash
git clone https://github.com/neverbreath/diploma-k8s.git
cd diploma-k8s
```

2. **Start the deployment:**

```bash
vagrant up
```

The process takes 10–15 minutes. Vagrant will automatically create three virtual machines, perform all required configuration (Docker, Kubernetes, network setup, application deployment).

3. **Check service availability** from the host machine:

- Frontend: [http://192.168.100.10:30080](http://192.168.100.10:30080) → expected message **"Hello from Frontend Container"**.
- Backend: [http://192.168.100.10:30500](http://192.168.100.10:30500) → expected JSON response **"Hello from Backend API!"**.

## Verifying Cluster Operation

You can manage the Kubernetes cluster from the host machine by copying the `admin.conf` configuration from the repository:

```bash
mkdir -p ~/.kube
cp configs/admin.conf ~/.kube/config
sed -i 's/127.0.0.1/192.168.100.10/' ~/.kube/config
kubectl get nodes
```

Expected output:

```text
NAME           STATUS   ROLES           AGE   VERSION
prod-server    Ready    control-plane   10m   v1.xx.x
```

To check pods and services:

```bash
kubectl get pods -A
kubectl get svc -A
```

## Additional Features

### Access to Kubernetes Dashboard

The official Kubernetes Dashboard is deployed on `prod-server`. **To access it from the host machine**:

1. **Connect to `prod-server`**:

```bash
vagrant ssh prod-server
```

2. **Start the proxy**:

```bash
kubectl proxy --address=0.0.0.0 --accept-hosts='.*' &
```

3. **On the host, open in a browser**:

```text
http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/
```

4. **Obtain a token for login**:

```bash
kubectl -n kubernetes-dashboard create token admin-user
```

### Image Vulnerability Scanning (Trivy)

The Trivy security scanner can be installed on `dev-workstation`. To check built images:

```bash
vagrant ssh dev-workstation
sudo -u developer trivy image 192.168.100.10:5000/frontend:v1
sudo -u developer trivy image 192.168.100.10:5000/backend:v1
```

If needed, install Trivy according to the official documentation (it is not installed automatically).

## Manual Deployment (Without Vagrant)

If you prefer to deploy the environment manually (e.g., on existing machines), use [/docs/manual-deploy.md](/docs/manual-deploy.md). It describes all steps corresponding to the technical part of the diploma project.
