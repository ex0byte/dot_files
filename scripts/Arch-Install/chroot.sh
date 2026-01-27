#!/usr/bin/env bash
set -e
source /root/ui.sh

info "Starting chroot configuration..."

### Timezone 
ln -sf /usr/share/zoneinfo/"$TIMEZONE" /etc/localtime
hwclock --systohc
ok "Timezone set"

### Locale 
echo "$LOCALE UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf
ok "Locale set"

### Hostname 
echo "$HOSTNAME" > /etc/hostname
cat >> /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
EOF
ok "Hostname configured"

### Root password 
echo "root:$ROOT_PASSWORD" | chpasswd
ok "Root password set"

### User account 
useradd -m -G wheel -s /bin/bash "$USERNAME"
echo "$USERNAME:$USER_PASSWORD" | chpasswd
ok "User $USERNAME created"

### Sudoers 
sed -i 's/^# \(%wheel ALL=(ALL) ALL\)/\1/' /etc/sudoers
ok "Sudo configured"

### Initramfs (with encrypt hook) 
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect modconf block encrypt btrfs filesystems keyboard fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P
ok "Initramfs generated"

### GRUB installation ###
if [[ "$UEFI" == true ]]; then
    pacman -S --noconfirm grub efibootmgr
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
else
    pacman -S --noconfirm grub
    grub-install --target=i386-pc "$DISK"
fi

### Configuring GRUB for LUKS root ###
sed -i '/^GRUB_ENABLE_CRYPTODISK/d' /etc/default/grub
echo "GRUB_ENABLE_CRYPTODISK=y" >> /etc/default/grub

UUID=$(blkid -s UUID -o value "$ROOT_PART")
sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=$UUID:cryptroot root=/dev/mapper/cryptroot\"|" /etc/default/grub

grub-mkconfig -o /boot/grub/grub.cfg
ok "GRUB installed and configured"

### Enabling essential services ###
systemctl enable NetworkManager
systemctl enable sshd
ok "Essential services enabled"

info "Chroot configuration complete! You can exit and reboot."
