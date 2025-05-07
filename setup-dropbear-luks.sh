#!/bin/bash
# === Setup Dropbear to allow remote LUKS unlocking over SSH ===

set -e

BACKUP_DIR="./dropbear-backups-$(date +%Y%m%d%H%M%S)"
INITRAMFS_CONF="/etc/initramfs-tools/initramfs.conf"
DROPBEAR_AUTH_KEYS="/etc/dropbear/initramfs/authorized_keys"
DROPBEAR_CONF="/etc/dropbear/initramfs/dropbear.conf"

# Logging helper function
log() {
    echo -e "[INFO] $1"
}

error() {
    echo -e "[ERROR] $1" >&2
}

log "=== 🔐 Starting Dropbear LUKS Unlock Setup ==="

# 1. Create backup directory
log "Creating backup directory: $BACKUP_DIR"
mkdir -p "$BACKUP_DIR"

# 2. Backup critical files
log "Backing up critical files..."
[[ -f "$INITRAMFS_CONF" ]] && sudo cp "$INITRAMFS_CONF" "$BACKUP_DIR/initramfs.conf.bak"
[[ -f "$DROPBEAR_AUTH_KEYS" ]] && sudo cp "$DROPBEAR_AUTH_KEYS" "$BACKUP_DIR/authorized_keys.bak"
[[ -f "$DROPBEAR_CONF" ]] && sudo cp "$DROPBEAR_CONF" "$BACKUP_DIR/dropbear.conf.bak"
log "Backup complete."

# 3. Ensure dropbear-initramfs is installed
if ! dpkg -s dropbear-initramfs &> /dev/null; then
    log "Installing dropbear-initramfs..."
    sudo apt update && sudo apt install -y dropbear-initramfs
else
    log "dropbear-initramfs is already installed."
fi

# 4. Setup SSH key
log "Setting up SSH keys..."
if [[ -f ssh_auth ]]; then
    log "Found ssh_auth file. Installing authorized key..."
    sudo mkdir -p /etc/dropbear/initramfs
    sudo cp ssh_auth "$DROPBEAR_AUTH_KEYS"
    sudo chmod 600 "$DROPBEAR_AUTH_KEYS"
else
    log "No ssh_auth file found. Checking ~/.ssh/authorized_keys..."
    if [[ -f ~/.ssh/authorized_keys ]]; then
        log "Using ~/.ssh/authorized_keys for Dropbear."
        sudo mkdir -p /etc/dropbear/initramfs
        sudo cp ~/.ssh/authorized_keys "$DROPBEAR_AUTH_KEYS"
        sudo chmod 600 "$DROPBEAR_AUTH_KEYS"
    else
        error "No SSH keys found. Please add a key to ssh_auth or ~/.ssh/authorized_keys."
        exit 1
    fi
fi

# 5. Configure Dropbear options
log "Configuring Dropbear..."
echo "DROPBEAR_OPTIONS=\"-p 2222\"" | sudo tee "$DROPBEAR_CONF" > /dev/null
log "Dropbear will listen on port 2222."

# 6. Detect network interface and current config
log "Detecting current network setup..."
primary_iface=$(ip route | grep default | awk '{print $5}' | head -n 1)
ip_address=$(ip -4 addr show "$primary_iface" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1)
gateway=$(ip route | grep default | awk '{print $3}' | head -n 1)

# Convert CIDR to netmask
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
hostname=$(hostname)

log "Detected interface: $primary_iface"
log "Client IP: $ip_address"
log "Gateway: $gateway"
log "Netmask: $netmask"
log "Hostname: $hostname"

# 7. Prompt for static vs dynamic
read -p "❓ Do you want to use a STATIC IP during early boot? (y/n): " use_static
use_static=${use_static,,}  # to lowercase

autoconf="none"
if [[ "$use_static" == "y" ]]; then
    read -p "🌐 Confirm or enter STATIC IP [$ip_address]: " ip_input
    read -p "🌐 Confirm or enter GATEWAY [$gateway]: " gw_input
    read -p "🌐 Confirm or enter NETMASK [$netmask]: " mask_input
    read -p "🌐 Confirm or enter HOSTNAME [$hostname]: " hostname_input

    ip_address=${ip_input:-$ip_address}
    gateway=${gw_input:-$gateway}
    netmask=${mask_input:-$netmask}
    hostname=${hostname_input:-$hostname}
    autoconf="none"
else
    autoconf="dhcp"
fi

# 8. Configure initramfs.conf
log "Configuring initramfs.conf..."
sudo sed -i '/^IP=/d' "$INITRAMFS_CONF"
echo "IP=$ip_address::$gateway:$netmask:$hostname:$primary_iface:$autoconf" | sudo tee -a "$INITRAMFS_CONF" > /dev/null
log "IP configuration added: $ip_address::$gateway:$netmask:$hostname:$primary_iface:$autoconf"

# 9. Rebuild initramfs
log "Rebuilding initramfs..."
if ! sudo update-initramfs -u; then
    error "Failed to rebuild initramfs. Restoring backups..."
    [[ -f "$BACKUP_DIR/initramfs.conf.bak" ]] && sudo cp "$BACKUP_DIR/initramfs.conf.bak" "$INITRAMFS_CONF"
    [[ -f "$BACKUP_DIR/authorized_keys.bak" ]] && sudo cp "$BACKUP_DIR/authorized_keys.bak" "$DROPBEAR_AUTH_KEYS"
    [[ -f "$BACKUP_DIR/dropbear.conf.bak" ]] && sudo cp "$BACKUP_DIR/dropbear.conf.bak" "$DROPBEAR_CONF"
    log "Backups restored. Exiting."
    exit 1
fi

log "Setup complete! On next boot, connect with 'ssh -p 2222 root@$ip_address'"
log "Then unlock the drive with 'cryptroot-unlock'."
log "=== ✅ All Done ==="


