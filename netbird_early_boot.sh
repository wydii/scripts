#!/bin/bash

set -e

BACKUP_DIR="./netbird-backups-$(date +%Y%m%d%H%M%S)"
INITRAMFS_CONF="/etc/initramfs-tools/initramfs.conf"
NETBIRD_HOOK="/etc/initramfs-tools/hooks/netbird"
NETBIRD_BIN="/snap/bin/netbird"

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
[[ -f "$NETBIRD_HOOK" ]] && sudo cp "$NETBIRD_HOOK" "$BACKUP_DIR/netbird-hook.bak"
log "Backup complete."

# 3. Verify Netbird binary (Snap installation)
if ! [ -x "$NETBIRD_BIN" ]; then
    error "Netbird Snap not found at $NETBIRD_BIN. Please ensure Netbird is installed via Snap."
    exit 1
fi

# 4. Create the initramfs hook
log "Creating Netbird initramfs hook at $NETBIRD_HOOK"
sudo tee "$NETBIRD_HOOK" > /dev/null <<EOF
#!/bin/sh
set -e

PREREQ=""

prereqs() {
    echo "\$PREREQ"
}

case "\$1" in
prereqs)
    prereqs
    exit 0
    ;;
esac

. /usr/share/initramfs-tools/hook-functions

log_msg() {
    echo "[Netbird] \$1" >&2
}

# Ensure the Netbird binary is included
log_msg "Copying Netbird Snap binary..."
copy_exec /snap/bin/netbird /usr/bin/netbird

# Copy the Snap environment
log_msg "Copying Snap environment..."
if [ -d /snap ]; then
    copy_exec /snap /snap
fi

# Copy Netbird configuration if it exists
if [ -d /var/snap/netbird ]; then
    log_msg "Copying Netbird Snap configuration..."
    copy_exec /var/snap/netbird /var/snap/netbird
else
    log_msg "Warning: No Netbird Snap configuration found."
fi

log_msg "Netbird setup complete."
EOF

# 5. Set hook permissions
log "Setting hook permissions..."
sudo chmod +x "$NETBIRD_HOOK"

# 6. Rebuild initramfs
log "Rebuilding initramfs..."
if ! sudo update-initramfs -u; then
    error "Failed to rebuild initramfs. Restoring backups..."
    [[ -f "$BACKUP_DIR/initramfs.conf.bak" ]] && sudo cp "$BACKUP_DIR/initramfs.conf.bak" "$INITRAMFS_CONF"
    [[ -f "$BACKUP_DIR/netbird-hook.bak" ]] && sudo cp "$BACKUP_DIR/netbird-hook.bak" "$NETBIRD_HOOK"
    log "Backups restored. Exiting."
    exit 1
fi

log "Setup complete! Netbird will now start during early boot."
log "=== ✅ All Done ==="
