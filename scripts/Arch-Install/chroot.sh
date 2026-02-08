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

### Secure Boot
SECURE_BOOT=false
echo
prompt_read sb_choice "Do you want to enable Secure Boot now? [y/N]: "

if [[ $sb_choice =~ ^(y|Y|yes|YES)$ ]]; then
    info "Configuring Secure Boot..."
    
    pacman -S --noconfirm sbctl sbsigntools systemd-ukify
    
    if ! sbctl status | grep -q "Installed: ✓"; then
        sbctl create-keys
        sbctl enroll-keys
        ok "Secure Boot keys created and enrolled"
    else
        warn "Secure Boot keys already exist — skipping key creation"
    fi
    
    mkdir -p /etc/kernel
    cat > /etc/kernel/cmdline <<EOF
cryptdevice=UUID=$ROOT_UUID:cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@ rw
EOF
    
    mkdir -p /boot/EFI/Linux
    
    cat > /etc/mkinitcpio.d/linux.preset <<EOF
ALL_kver="/boot/vmlinuz-linux"
PRESETS=('default')
default_uki="/boot/EFI/Linux/arch-linux.efi"
EOF
    
    mkinitcpio -P
    sbctl sign /boot/EFI/Linux/arch-linux.efi
    
    cat > /boot/loader/entries/arch.conf <<EOF
title Arch Linux (Secure Boot)
efi   /EFI/Linux/arch-linux.efi
EOF
    
    sbctl sign-all
    sbctl enable
    
    ok "Secure Boot enabled"
    
    ### Pacman auto-sign hook ###
    info "Installing Secure Boot pacman hook..."
    
    mkdir -p /etc/pacman.d/hooks
    cat > /etc/pacman.d/hooks/90-secureboot-sign.hook <<'EOF'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = linux
Target = systemd
Target = systemd-boot
Target = linux-firmware
Target = amd-ucode
Target = intel-ucode

[Action]
Description = Signing EFI binaries for Secure Boot
When = PostTransaction
Exec = /usr/bin/sbctl sign-all
EOF
    
    ok "Secure Boot auto-sign hook installed"
else
    info "Secure Boot will not be configured"
fi

info "Chroot configuration complete! You can exit and reboot."
