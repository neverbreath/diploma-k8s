#!/bin/bash
set -e

# The script is run as a user with sudo access (e.g., vagrant or admin).
# All privileged operations use sudo.

echo "=== [Client] Starting setup ==="

# 1. Create user 'user' (if not already exists)
if ! id user &>/dev/null; then
    sudo useradd -m -s /bin/bash user
    echo "User 'user' created"
else
    echo "User 'user' already exists"
fi

# 2. Install curl — the main tool for checking HTTP availability
echo "--- Installing curl ---"
sudo apt-get update
sudo apt-get install -y curl

# 3. Add entry to /etc/hosts for convenient access to the server by name
echo "--- Configuring hosts ---"
echo "192.168.100.10 prod-server" | sudo tee -a /etc/hosts

# 4. Output verification instructions
echo "=== [Client] Setup completed ==="
echo "To check the availability of services, run the commands:"
echo "  curl http://192.168.100.10:30080"
echo "  curl http://192.168.100.10:30500"
echo "Or open the specified addresses in your browser."
