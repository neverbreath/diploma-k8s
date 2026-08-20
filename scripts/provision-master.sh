#!/bin/bash
set -e

# Скрипт выполняется от имени пользователя admin с правами sudo.
# Если запущен из Vagrant, пользователь admin уже существует.

echo "=== [Prod-Server] Начало настройки ==="

# 1. Отключение swap и настройка сетевого стека
echo "--- Отключение swap ---"
sudo swapoff -a
sudo sed -i '/swap/d' /etc/fstab
sudo modprobe br_netfilter
echo "net.bridge.bridge-nf-call-iptables = 1" | sudo tee -a /etc/sysctl.d/k8s.conf
echo "net.bridge.bridge-nf-call-ip6tables = 1" | sudo tee -a /etc/sysctl.d/k8s.conf
sudo sysctl --system

# 2. Установка необходимых пакетов
echo "--- Установка Docker и Kubernetes ---"
sudo apt-get update
sudo apt-get install -y docker-engine kubeadm kubelet kubectl crictl

# 3. Запуск служб
echo "--- Запуск Docker и kubelet ---"
sudo systemctl enable --now docker
sudo systemctl enable --now kubelet

# 4. Добавление записи в /etc/hosts
echo "--- Настройка hosts ---"
echo "192.168.100.10 prod-server prod-server.local" | sudo tee -a /etc/hosts

# 5. Инициализация кластера Kubernetes
echo "--- Инициализация kubeadm ---"
sudo kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address=192.168.100.10

# 6. Копирование конфигурации kubectl в домашний каталог admin
echo "--- Копирование kubeconfig ---"
mkdir -p $HOME/.kube
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# 7. Установка сетевого плагина Flannel
echo "--- Установка Flannel ---"
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml

# 8. Снятие taint с control-plane (для одноузлового кластера)
echo "--- Снятие taint ---"
kubectl taint nodes $(hostname) node-role.kubernetes.io/control-plane:NoSchedule- || true

# 9. Генерация самоподписанного сертификата для Docker Registry
echo "--- Создание сертификата для registry ---"
sudo mkdir -p /certs
sudo openssl req -newkey rsa:4096 -nodes -sha256 -keyout /certs/registry.key \
  -x509 -days 365 -out /certs/registry.crt -subj "/CN=192.168.100.10"

# 10. Запуск приватного Docker Registry с TLS
echo "--- Запуск registry ---"
# Требуется, чтобы admin был в группе docker, иначе используем sudo docker.
# Поскольку мы не добавляли admin в группу docker в Vagrantfile, используем sudo.
sudo docker run -d --restart=always --name registry \
  -v /certs:/certs \
  -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/registry.crt \
  -e REGISTRY_HTTP_TLS_KEY=/certs/registry.key \
  -p 5000:5000 registry:2

# 11. Ожидание готовности узла
echo "--- Ожидание готовности кластера ---"
kubectl wait --for=condition=Ready node --all --timeout=180s

# 12. Применение манифестов Kubernetes из /vagrant/kubernetes
echo "--- Применение манифестов ---"
sudo chmod -R a+r /vagrant/kubernetes   # чтобы admin мог читать
kubectl apply -f /vagrant/kubernetes/

# 13. Копирование сертификата реестра в /vagrant/configs для Dev-Workstation
echo "--- Копирование сертификата в /vagrant/configs ---"
sudo cp /certs/registry.crt /vagrant/configs/registry.crt

echo "=== [Prod-Server] Настройка завершена ==="