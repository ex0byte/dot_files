#!/usr/bin/env bash
set -e
source /root/ui.sh

info "Starting chroot configuration..."

### Load passwords from secrets file (never passed via env) ###
if [[ -z "$SECRETS_FILE" || ! -f "$SECRETS_FILE" ]]; then
    die "SECRETS_FILE not set or missing — cannot set passwords"
fi
# shellcheck source=/dev/null
source "$SECRETS_FILE"

### Validate required env vars ###
for var in TIMEZONE LOCALE HOSTNAME USERNAME ROOT_PART USER_PASSWORD ROOT_PASSWORD; do
    [[ -n "${!var}" ]] || die "Required variable $var is not set"
done

### Checking for EFI ###
mountpoint -q /boot || die "/boot is not mounted (EFI partition missing)"

### Timezone ###
ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
hwclock --systohc
ok "Timezone set to $TIMEZONE"

### Locale ###
grep -q "^#*$LOCALE UTF-8" /etc/locale.gen || die "Locale $LOCALE not found in locale.gen"
sed -i "s/^#\($LOCALE UTF-8\)/\1/" /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf
ok "Locale set to $LOCALE"

### Hostname ###
echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
EOF
ok "Hostname configured: $HOSTNAME"

### Root password ###
echo "root:$ROOT_PASSWORD" | chpasswd
ok "Root password set"

### User account ###
if ! id "$USERNAME" &>/dev/null; then
    useradd -m -G wheel -s /bin/bash "$USERNAME"
    ok "User $USERNAME created"
else
    ok "User $USERNAME already exists"
fi
echo "$USERNAME:$USER_PASSWORD" | chpasswd
ok "User password set"

### Sudoers ###
if ! grep -q "^%wheel ALL=(ALL:ALL) ALL" /etc/sudoers; then
    sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
fi
ok "Sudo configured"

### Clear passwords from memory as early as possible ###
unset USER_PASSWORD ROOT_PASSWORD

### Initramfs ###
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect keyboard modconf block encrypt btrfs filesystems fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P
ok "Initramfs generated"

### systemd-boot ###
bootctl install
ok "systemd-boot installed"

mkdir -p /boot/loader
cat > /boot/loader/loader.conf <<EOF
default arch.conf
timeout 3
editor no
EOF

### Boot entries ###
UUID=$(blkid -s UUID -o value "$ROOT_PART")
ROOT_UUID="$UUID"   # alias used in Secure Boot section below

mkdir -p /boot/loader/entries

cat > /boot/loader/entries/arch.conf <<EOF
title   Arch Linux
linux   /vmlinuz-linux
initrd  /amd-ucode.img
initrd  /initramfs-linux.img
options cryptdevice=UUID=$UUID:cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@ rw quiet
EOF

cat > /boot/loader/entries/arch-fallback.conf <<EOF
title   Arch Linux (fallback initramfs)
linux   /vmlinuz-linux
initrd  /amd-ucode.img
initrd  /initramfs-linux-fallback.img
options cryptdevice=UUID=$UUID:cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@ rw
EOF

ok "Boot entries created (main + fallback)"

### Essential services (already pacstrapped, just enable) ###
systemctl enable NetworkManager
systemctl enable sshd
ok "Essential services enabled"

### Secure Boot (optional) ###
echo
prompt_read sb_choice "Enable Secure Boot now? [y/N]:"

if [[ $sb_choice =~ ^(y|Y|yes|YES)$ ]]; then
    info "Configuring Secure Boot..."

    pacman -S --noconfirm sbctl sbsigntools systemd-ukify

    if ! sbctl status | grep -q "Installed: ✓"; then
        sbctl create-keys
        sbctl enroll-keys --microsoft
        ok "Secure Boot keys created and enrolled"
    else
        warn "Secure Boot keys already exist — skipping key creation"
    fi

    mkdir -p /etc/kernel
    cat > /etc/kernel/cmdline <<EOF
cryptdevice=UUID=$ROOT_UUID:cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@ rw quiet
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
title   Arch Linux (Secure Boot)
efi     /EFI/Linux/arch-linux.efi
EOF

    sbctl sign-all
    sbctl verify

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
    info "Skipping Secure Boot configuration"
fi

ok "Chroot configuration complete!"
info "Type 'exit', then unmount and reboot:"
info "  umount -R /mnt && reboot"