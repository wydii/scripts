#!/bin/bash
# === Setup Dropbear to allow remote LUKS unlocking over SSH ===

set -e

echo -e "\n=== 🔐 Starting Dropbear LUKS Unlock Setup ==="

# 1. Ensure dropbear-initramfs is installed
if ! dpkg -s dropbear-initramfs &> /dev/null; then
    echo "📦 Installing dropbear-initramfs..."
    sudo apt update && sudo apt install -y dropbear-initramfs
else
    echo "✅ dropbear-initramfs is already installed."
fi

# 2. Setup SSH key
echo "---- 🔑 Setting up SSH keys ----"
if [[ -f ssh_auth ]]; then
    echo "✅ Found ssh_auth file. Installing authorized key..."
    sudo mkdir -p /etc/dropbear/initramfs
    sudo cp ssh_auth /etc/dropbear/initramfs/authorized_keys
    sudo chmod 600 /etc/dropbear/initramfs/authorized_keys
else
    echo "⚠️  No ssh_auth file found."
    
    if [[ -f ~/.ssh/authorized_keys ]]; then
        read -p "❓ Use your current ~/.ssh/authorized_keys for Dropbear? (y/n): " use_existing_keys
        if [[ "$use_existing_keys" =~ ^[Yy]$ ]]; then
            echo "✅ Using ~/.ssh/authorized_keys for Dropbear."
            sudo mkdir -p /etc/dropbear/initramfs
            sudo cp ~/.ssh/authorized_keys /etc/dropbear/initramfs/authorized_keys
            sudo chmod 600 /etc/dropbear/initramfs/authorized_keys
        else
            echo "❌ ERROR: No SSH keys provided. Please add a key to ssh_auth or ~/.ssh/authorized_keys."
            exit 1
        fi
    else
        echo "❌ ERROR: Neither ssh_auth nor ~/.ssh/authorized_keys found."
        exit 1
    fi
fi

# 3. Detect network interface and current config
echo "---- 🌐 Detecting current network setup ----"
primary_iface=$(ip route | grep default | awk '{print $5}' | head -n 1)
ip_address=$(ip -4 addr show "$primary_iface" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1)
gateway=$(ip route | grep default | awk '{print $3}' | head -n 1)
cidr=$(ip -o -f inet addr show "$primary_iface" | awk '{print $4}' | cut -d/ -f2 | head -n 1)

function cidr_to_netmask() {
    local i mask=""
    local bits=$1
    for ((i=0; i<4; i++)); do
        if ((bits >= 8)); then
            mask+=255
            bits=$((bits - 8))
        else
            mask+=$((256 - 2**(8 - bits)))
            bits=0
        fi
        [[ $i -lt 3 ]] && mask+=.
    done
    echo $mask
}

netmask=$(cidr_to_netmask "$cidr")

echo "✅ Detected:"
echo "   ➤ Interface: $primary_iface"
echo "   ➤ IP: $ip_address"
echo "   ➤ Gateway: $gateway"
echo "   ➤ Netmask: $netmask"

# 4. Prompt for static vs dynamic
read -p "❓ Do you want to use a STATIC IP during early boot? (y/n): " use_static
use_static=${use_static,,}  # to lowercase

if [[ "$use_static" == "y" ]]; then
    read -p "🌐 Confirm or enter STATIC IP [$ip_address]: " ip_input
    read -p "🌐 Confirm or enter GATEWAY [$gateway]: " gw_input
    read -p "🌐 Confirm or enter NETMASK [$netmask]: " mask_input

    ip_address=${ip_input:-$ip_address}
    gateway=${gw_input:-$gateway}
    netmask=${mask_input:-$netmask}

    echo "✅ Using static config:"
    echo "   ➤ IP: $ip_address"
    echo "   ➤ Gateway: $gateway"
    echo "   ➤ Netmask: $netmask"

    echo "💾 Writing static config to /etc/initramfs-tools/initramfs.conf"
    echo "IP=$ip_address::$gateway:$netmask::${primary_iface}:none" | sudo tee /etc/initramfs-tools/initramfs.conf > /dev/null
else
    echo "ℹ️ Keeping DHCP (dynamic IP) — clearing initramfs.conf IP config."
    sudo sed -i '/^IP=/d' /etc/initramfs-tools/initramfs.conf
fi

# 5. Rebuild initramfs
echo "---- 🛠️ Rebuilding initramfs ----"
sudo update-initramfs -u

echo -e "\n🎉 Dropbear early boot SSH setup is complete!"
echo "You can connect after reboot with:"
echo "   ssh -p 2222 root@$ip_address"
echo "Then unlock the drive using:"
echo "   cryptroot-unlock"

echo -e "\n==== ✅ All Done ====\n"

