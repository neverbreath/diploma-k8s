
---

```markdown
# Architecture of the Laboratory Environment

## 1. General Overview

The environment simulates the infrastructure of a small enterprise where a container management system based on Docker and Kubernetes is deployed. It consists of three virtual machines connected to an isolated local network `192.168.100.0/24`.

+---------------------+
| Host System |
| (Vagrant/VirtualBox)|
+----------+----------+
|
+----------------------+----------------------+
| | |
+-------v-------+ +-------v-------+ +-------v-------+
| prod-server | | dev-workstation| | client |
| (Master) | | (Developer) | | (Verifier) |
| IP: .10 |<---->| IP: .20 | | IP: .30 |
+---------------+ +---------------+ +---------------+


All machines run **Alt Linux 10.4** (Server or Workstation). Communication between them takes place over the VirtualBox internal network (host-only or private network).

## 2. Virtual Machine Roles

### 2.1. Prod-Server (192.168.100.10)

**OS:** Alt Server 10.4  
**Main functions:**
- **Kubernetes control-plane node.** All orchestrator components run here: API server, etcd, controller manager, scheduler.
- **Private Docker Registry.** A `registry:2` container with TLS (self-signed certificate) is deployed, listening on port `5000`.
- **Image storage.** Docker Engine is also present on this node to load and publish images to the registry.
- **Kubernetes Dashboard.** The official web interface is installed for visual cluster monitoring (access via `kubectl proxy`).

**System settings:**
- Swap disabled.
- `br_netfilter` module loaded, `bridge-nf-call-iptables` and `bridge-nf-call-ip6tables` parameters activated.
- `/etc/hosts` entry added: `192.168.100.10 prod-server`.
- Taint removed from control-plane to allow user pods to run on the single node.

### 2.2. Dev-Workstation (192.168.100.20)

**OS:** Alt Workstation 10.4  
**Main functions:**
- **Developer workspace.** Contains source code of test applications and Dockerfiles.
- **Docker image building.** Docker Engine installed. User `developer` is a member of the `docker` group.
- **Image publication.** `docker push` to the private registry on `prod-server`.
- **Cluster management.** `kubectl` installed and configured to connect to the `prod-server` API server.
- **Dashboard access.** Can run `kubectl proxy` to reach the web interface.

**System settings:**
- Registry certificate placed in `/etc/docker/certs.d/192.168.100.10:5000/` for trust.
- `admin.conf` copied to `~/.kube/config` with the server address replaced by `192.168.100.10`.

### 2.3. Client (192.168.100.30)

**OS:** Alt Workstation 10.4  
**Main functions:**
- **Verification of service availability.** This machine sends HTTP requests to Kubernetes NodePort services.
- No specialized software is installed (only a browser or `curl`).

## 3. Network Configuration

| Component                | Address / Port               | Description                                      |
|--------------------------|------------------------------|--------------------------------------------------|
| VM network               | 192.168.100.0/24             | Isolated VirtualBox network                      |
| Kubernetes API server    | https://192.168.100.10:6443  | Management API                                   |
| Private Docker Registry  | 192.168.100.10:5000          | Image push/pull over TLS                         |
| Frontend Service (NodePort) | 192.168.100.10:30080      | Access to Nginx frontend                         |
| Backend Service (NodePort)  | 192.168.100.10:30500      | Access to Flask backend                          |
| Kubernetes Dashboard     | (via kubectl proxy)          | Local proxy on dev-workstation or prod-server    |

## 4. Software and Versions

| Component           | Version (approximate)            | Note                                      |
|---------------------|-----------------------------------|-------------------------------------------|
| Alt Linux           | 10.4 (Server and Workstation)     | Domestic distribution                      |
| Docker Engine       | latest from Alt repository        |                                           |
| Kubernetes          | 1.27.x (depends on repository)    | kubeadm, kubelet, kubectl                 |
| Flannel             | latest stable                     | CNI plugin                                |
| Docker Registry     | 2                                 | Official image                            |
| Nginx               | alpine                            | Base image for frontend                   |
| Python              | 3.x (alpine)                      | Base image for backend                    |
| Flask               | 2.x                               | Specified in requirements.txt             |

Exact versions may differ; they are fixed at the time of deployment.

## 5. Data Flow and Application Lifecycle

1. **Image building.**  
   On `dev-workstation`, the developer (user `developer`) builds two images:
   - `frontend:v1` – based on `nginx:alpine`, copies `index.html` to `/usr/share/nginx/html`.
   - `backend:v1` – based on `python:alpine`, installs Flask and runs `app.py`.

2. **Publication to the private registry.**  
   Images are tagged with the registry address (`192.168.100.10:5000/...`) and pushed using `docker push`. The registry on `prod-server` accepts images over TLS.

3. **Deployment to Kubernetes.**  
   Using `kubectl apply -f kubernetes/`, the following resources are created in the cluster:
   - Namespace `apps` (with Pod Security Standards labels `restricted`).
   - Deployment `frontend` (2 replicas, later scaled to 4).
   - Service `frontend-svc` (NodePort 30080 → container port 80).
   - Deployment `backend` (2 replicas).
   - Service `backend-svc` (NodePort 30500 → container port 5000).
   - RBAC: role `pod-manager`, binding to ServiceAccount `developer`.
   - NetworkPolicy: allows incoming traffic to backend only from pods with label `app: frontend`.
   - Resources for Kubernetes Dashboard (ServiceAccount `admin-user` and ClusterRoleBinding).

4. **End-user access.**  
   From the `client` machine, HTTP requests are made to NodePort services. Kubernetes routes traffic to the appropriate pods via kube-proxy and Flannel.

## 6. Security

The following security measures are implemented in the environment:

- **Container privilege restriction:**  
  When manually running containers, flags `--cap-drop=ALL --read-only` are used (demonstration). Deployment manifests include `securityContext` with minimal privileges if required.
- **Docker Content Trust (DCT):**  
  Can be enabled on `dev-workstation` for image signing and verification (not enabled by default due to manual key management).
- **Vulnerability scanning:**  
  Trivy is installed on `dev-workstation` to analyze images for CVEs.
- **RBAC:**  
  A dedicated ServiceAccount `developer` is created with a limited role `pod-manager` (rights only to manage pods in the `apps` namespace). Administrative actions are performed via `admin.conf` (cluster admin).
- **NetworkPolicy:**  
  Backend pods accept traffic only from frontend pods, blocking direct external access.
- **Pod Security Standards:**  
  The `apps` namespace is labeled with `pod-security.kubernetes.io/enforce: restricted`, which prohibits privileged pods, running as root, etc.
- **Network isolation:**  
  All machines are on a separate virtual network with no direct internet access (only through the host if needed).

## 7. Scalability and Fault Tolerance

- The number of replicas in a Deployment can be changed with the command `kubectl scale deployment frontend --replicas=4`. In the current configuration (single node), all pods are placed on `prod-server`, but when worker nodes are added, Kubernetes automatically distributes the load.
- The private registry runs as a single instance, which is acceptable for a laboratory environment. For production, a highly available storage (e.g., S3 or external registry) is recommended.

## 8. Conclusion

This architecture demonstrates the complete containerization cycle: from writing code and building an image to orchestration and security enforcement. It is built on the domestic Alt Linux OS, which aligns with import substitution requirements and can serve as a foundation for real small business projects.

All components are automated with Vagrant and shell scripts, ensuring reproducibility and ease of deployment.