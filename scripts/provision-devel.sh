#!/bin/bash
set -e

# Скрипт выполняется от имени пользователя developer с правами sudo.
# Пользователь developer уже создан в Vagrantfile.

echo "=== [Dev-Workstation] Начало настройки ==="

# 1. Установка Docker
echo "--- Установка Docker ---"
sudo apt-get update
sudo apt-get install -y docker-engine
sudo systemctl enable --now docker

# 2. Добавление текущего пользователя (developer) в группу docker (если ещё не добавлен)
sudo usermod -aG docker $USER

# 3. Установка kubectl
echo "--- Установка kubectl ---"
sudo apt-get install -y kubectl

# 4. Настройка доступа к приватному Docker Registry (сертификат)
echo "--- Настройка доверия к приватному реестру ---"
sudo mkdir -p /etc/docker/certs.d/192.168.100.10:5000
sudo cp /vagrant/configs/registry.crt /etc/docker/certs.d/192.168.100.10:5000/ca.crt

# 5. Копирование kubeconfig в домашний каталог developer
echo "--- Копирование kubeconfig ---"
mkdir -p $HOME/.kube
sudo cp /vagrant/configs/admin.conf $HOME/.kube/config
sudo chown -R $(id -u):$(id -g) $HOME/.kube
# Замена адреса API-сервера с 127.0.0.1 на реальный IP
sed -i 's/127\.0\.0\.1/192.168.100.10/g' $HOME/.kube/config

# 6. Сборка и публикация образов в приватный реестр
echo "--- Сборка и публикация frontend и backend ---"
# Так как docker требует прав root или членства в группе docker,
# а текущая сессия ещё не перечитала группы (usermod выше), 
# мы можем выполнить docker через sudo или запустить новый su.
# Проще: использовать sudo docker для сборки? 
# Но сборка из-под root может создать файлы с root-владельцем, что нежелательно.
# Лучше выполнить команды в новом su, где группа docker уже активна.
# Или перезапустить сессию? В скрипте мы можем сделать:
#   exec sg docker -c "bash /vagrant/scripts/build_and_push.sh"
# Но для простоты предположим, что пользователь developer добавлен в группу docker в Vagrantfile
# и перелогин уже произошёл (после создания пользователя и добавления в группу, 
# затем мы запускаем основной скрипт через su - developer, который читает группы заново).
# Поэтому можно запускать docker без sudo.
cd /vagrant/docker/frontend
docker build -t frontend:v1 .
docker tag frontend:v1 192.168.100.10:5000/frontend:v1
docker push 192.168.100.10:5000/frontend:v1

cd /vagrant/docker/backend
docker build -t backend:v1 .
docker tag backend:v1 192.168.100.10:5000/backend:v1
docker push 192.168.100.10:5000/backend:v1

echo "=== [Dev-Workstation] Настройка завершена ==="