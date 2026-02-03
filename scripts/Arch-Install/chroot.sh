#!/usr/bin/env bash
set -e
source /root/ui.sh

info "Starting chroot configuration..."

### Checking for EFI ###
mountpoint -q /boot || die "/boot is not mounted (EFI partition missing)"

### Timezone 
ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
hwclock --systohc
ok "Timezone set"

### Locale 
grep -q "^#*$LOCALE UTF-8" /etc/locale.gen || die "Locale $LOCALE not found in locale.gen"
sed -i "s/^#\($LOCALE UTF-8\)/\1/" /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf
ok "Locale set"

### Hostname 
echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
EOF
ok "Hostname configured"

### Root password 
echo "root:$ROOT_PASSWORD" | chpasswd
ok "Root password set"

### User account 
if ! id "$USERNAME" &>/dev/null; then
    useradd -m -G wheel -s /bin/bash "$USERNAME"
    ok "User $USERNAME created"
else
    ok "User $USERNAME already exists"
fi
echo "$USERNAME:$USER_PASSWORD" | chpasswd

### Sudoers 
if ! grep -q "^%wheel ALL=(ALL:ALL) ALL" /etc/sudoers; then
    sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
fi
ok "Sudo configured"

### Initramfs 
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect keyboard modconf block encrypt btrfs filesystems fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P
ok "Initramfs generated"

### systemd-boot ###
bootctl install
ok "systemd-boot installed"

mkdir -p /boot/loader
cat > /boot/loader/loader.conf <<EOF
default arch
timeout 3
editor no
EOF

### Boot entry ###
UUID=$(blkid -s UUID -o value "$ROOT_PART")

mkdir -p /boot/loader/entries
cat > /boot/loader/entries/arch.conf <<EOF
title   Arch Linux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options cryptdevice=UUID=$UUID:cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@ rw
EOF

ok "Boot entry created"

### Enabling essential services ###
pacman -S --noconfirm networkmanager openssh
systemctl enable NetworkManager
systemctl enable sshd
ok "Essential services enabled"

info "Chroot configuration complete! You can exit and reboot."
