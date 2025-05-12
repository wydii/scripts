#!/bin/bash

set -e

BACKUP_DIR="./netbird-backups-$(date +%Y%m%d%H%M%S)"
INITRAMFS_CONF="/etc/initramfs-tools/initramfs.conf"

# Logging helper function
log() {
    echo -e "[INFO] $1"
}

error() {
    echo -e "[ERROR] $1" >&2
}

log "=== 🌐 Starting Netbird Early Boot Setup ==="

# 1. Create backup directory
log "Creating backup directory: $BACKUP_DIR"
mkdir -p "$BACKUP_DIR"

# 2. Backup critical files
log "Backing up critical files..."
[[ -f "$INITRAMFS_CONF" ]] && sudo cp "$INITRAMFS_CONF" "$BACKUP_DIR/initramfs.conf.bak"
log "Backup complete."

# 3. Ensure Netbird is installed
if ! command -v netbird &> /dev/null; then
    error "Netbird is not installed. Please install it before running this script."
    exit 1
fi

# 4. Create initramfs hook for Netbird
NETBIRD_HOOK="/etc/initramfs-tools/hooks/netbird"
log "Creating Netbird initramfs hook..."
sudo mkdir -p /etc/initramfs-tools/hooks
sudo tee "$NETBIRD_HOOK" << 'EOF'
#!/bin/sh
PREREQ=""

prereqs() {
    echo "$PREREQ"
}

case "$1" in
prereqs)
    prereqs
    exit 0
    ;;
esac

# Add the Netbird binary and configuration to the initramfs
. /usr/share/initramfs-tools/hook-functions
copy_exec /usr/bin/netbird /usr/bin/netbird
copy_exec /usr/lib/netbird /usr/lib/netbird
copy_exec /etc/netbird /etc/netbird
EOF

sudo chmod +x "$NETBIRD_HOOK"
log "Netbird hook created."

# 5. Create wait script for Netbird connection
NETBIRD_WAIT="/etc/initramfs-tools/scripts/init-bottom/netbird-wait"
log "Creating Netbird wait script..."
sudo mkdir -p /etc/initramfs-tools/scripts/init-bottom
sudo tee "$NETBIRD_WAIT" << 'EOF'
#!/bin/sh

# Wait for Netbird to establish a connection
echo "[INFO] Waiting for Netbird to connect..."
while ! /usr/bin/netbird status | grep -q 'Connected'; do
    sleep 2
done

echo "[INFO] Netbird is connected. Continuing boot..."
EOF

sudo chmod +x "$NETBIRD_WAIT"
log "Netbird wait script created."

# 6. Rebuild initramfs
log "Rebuilding initramfs..."
sudo update-initramfs -u

log "Setup complete! Netbird will now start during early boot."
log "=== ✅ All Done ==="
