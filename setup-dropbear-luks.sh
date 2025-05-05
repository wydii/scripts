#!/bin/bash
# === Setup Dropbear to allow remote LUKS unlocking over SSH ===

set -e

echo "==== Starting Dropbear LUKS unlock setup ===="

# 1. Check if dropbear-initramfs is installed
if ! dpkg -l | grep -q dropbear-initramfs; then
    echo "❌ Dropbear-initramfs is not installed."
    echo "Installing dropbear-initramfs..."
    sudo apt update
    sudo apt install -y dropbear-initramfs
    echo "✅ Dropbear-initramfs installed."
else
    echo "✅ Dropbear-initramfs is already installed."
fi

# 2. Create Dropbear authorized_keys from file
echo "---- Setting up authorized SSH keys from file ----"

# Check if the ssh_auth file exists in the current directory
if [ -f "ssh_auth" ]; then
    echo "✅ Found ssh_auth file. Adding SSH key to authorized_keys."
    sudo mkdir -p /etc/dropbear-initramfs
    sudo cp "ssh_auth" /etc/dropbear-initramfs/authorized_keys
else
    echo "❌ ssh_auth file not found in current directory. Please create a file named 'ssh_auth' with your SSH public key."
    exit 1
fi

# 3. (Optional) Change Dropbear port
DROPBEAR_CONFIG_FILE="/etc/dropbear-initramfs/config"
PORT="2222" # you can change it here

echo "---- Configuring Dropbear ----"
echo "DROPBEAR_OPTIONS=\"-p $PORT\"" | sudo tee "$DROPBEAR_CONFIG_FILE" > /dev/null
echo "✅ Dropbear will listen on port $PORT during early boot."

# 4. (Optional) Static IP setup for initramfs
echo "---- Checking static IP config ----"
INITRAMFS_CONF="/etc/initramfs-tools/initramfs.conf"

read -rp "❓ Do you want to set a STATIC IP? (y/n): " setstatic
if [[ "$setstatic" =~ ^[Yy]$ ]]; then
    read -rp "🌐 Enter STATIC IP (e.g., 192.168.1.100): " staticip
    read -rp "🌐 Enter GATEWAY IP (e.g., 192.168.1.1): " gatewayip
    read -rp "🌐 Enter NETMASK (e.g., 255.255.255.0): " netmask

    echo "DEVICE=eth0" | sudo tee -a "$INITRAMFS_CONF" > /dev/null
    echo "IP=${staticip}::${gatewayip}:${netmask}::eth0:off" | sudo tee -a "$INITRAMFS_CONF" > /dev/null
    echo "✅ Static IP configured for early boot."
else
    echo "🌐 Using DHCP during early boot (default)."
fi

# 5. Rebuild initramfs
echo "---- Rebuilding initramfs ----"
sudo update-initramfs -u
echo "✅ initramfs rebuilt."

# 6. Done
echo "🎉 Setup complete! On next boot, Dropbear will start BEFORE decryption."
echo "You can connect via: ssh -p $PORT root@<server-ip>"
echo "Then unlock the drive manually with:"
echo "    cryptroot-unlock"

echo "==== All Done! ===="
