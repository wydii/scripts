chmod +x hook-netbird
chmod +x start-netbird

rm /etc/initramfs-tools/hooks/hook-netbird
rm /etc/initramfs-tools/scripts/init-premount/start-netbird

cp hook-netbird /etc/initramfs-tools/hooks/
cp start-netbird /etc/initramfs-tools/scripts/init-premount/

update-initramfs -u

