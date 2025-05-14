chmod +x hook-netbird
chmod +x start-netbird

echo "Removing existing hooks and scripts"
rm /etc/initramfs-tools/hooks/hook-netbird
rm /etc/initramfs-tools/scripts/init-premount/start-netbird

echo "Copying new hooks and scripts"
cp hook-netbird /etc/initramfs-tools/hooks/
cp start-netbird /etc/initramfs-tools/scripts/init-premount/

echo "Updating initramfs"
update-initramfs -u

echo "Done"
