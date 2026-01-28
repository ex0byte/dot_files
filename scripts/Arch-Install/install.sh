#!/usr/bin/env bash
set -e
source "$(dirname "$0")/lib/ui.sh"

info "Starting Arch Installation......"

### Detecting UFEI/BIOS ###
UEFI=false
if [[ -d /sys/firmware/efi/efivars ]]; then
    UEFI=true
    info "UEFI system detected"
else
    info "BIOS system detected"
fi

### Selecting Disk ###
echo
info "Available disks:"
lsblk -d -e 7 -o NAME,SIZE,MODEL
echo

while true; do
    prompt_read DISK "Disk (name only, e.g., nvme0n1):"
    DISK="/dev/$DISK"
    [[ -b "$DISK" && $(lsblk -dn -o NAME "$DISK") == "$(basename "$DISK")" ]] && break
    fail "'$DISK' is not a valid block device"
done
ok "Selected $DISK"

### Prompts for Timezone / Locale / Hostname / Username / Passwords ###
while true; do
    prompt_read TIMEZONE "Timezone (e.g., Asia/Kolkata):"
    [[ -f "/usr/share/zoneinfo/$TIMEZONE" ]] && break
    fail "Invalid timezone '$TIMEZONE'"
done
ok "Timezone set"

while true; do
    prompt_read LOCALE "Enter the locale (e.g., en_US.UTF-8):"
    grep -qF "$LOCALE UTF-8" /etc/locale.gen && break
    fail "Locale '$LOCALE' not found in /etc/locale.gen"
done
ok "Locale set"

while true; do
    prompt_read HOSTNAME "Hostname (letters, digits, hyphens only):"
    [[ "$HOSTNAME" =~ ^[a-zA-Z0-9-]+$ ]] && break
    fail "Invalid hostname"
done

while true; do
    prompt_read USERNAME "Username (lowercase letters, digits, _ or -; start with letter/_):"
    [[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]] && break
    fail "Invalid username"
done

### User password
while true; do
    prompt_read_password USER_PASSWORD "User password:"
    prompt_read_password CONFIRM_PASSWORD "Confirm user password:"
    [[ "$USER_PASSWORD" == "$CONFIRM_PASSWORD" ]] && break
    fail "Passwords do not match"
done
ok "User password set"

### Root password
while true; do
    prompt_read_password ROOT_PASSWORD "Root password:"
    prompt_read_password CONFIRM_ROOT "Confirm root password:"
    [[ "$ROOT_PASSWORD" == "$CONFIRM_ROOT" ]] && break
    fail "Root passwords do not match"
done
ok "Root password set"

### LUKS Passphrase
while true; do
    prompt_read_password LUKS_PASSWORD "Enter LUKS passphrase for root:"
    prompt_read_password CONFIRM_LUKS "Confirm LUKS passphrase:"
    [[ "$LUKS_PASSWORD" == "$CONFIRM_LUKS" ]] && break
    fail "LUKS passphrases do not match"
done
ok "LUKS passphrase set"

echo
warn "Please confirm the settings below:"
echo "Disk:     $DISK"
warn "ALL DATA ON $DISK WILL BE ERASED IF YOU CHOOSE WIPE"
echo "Hostname: $HOSTNAME"
echo "Username: $USERNAME"

confirm "Proceed with installation" || die "Installation aborted"
ok "Proceeding with installation"

timedatectl set-ntp true

### Asking if Dual-boot / Disk Wipe ###
if ! confirm "Wipe entire disk? (No = dual boot safe)"; then
    WIPE_DISK=false
    warn "Dual-boot mode: existing partitions preserved, new encrypted root will be created."
    
    if $UEFI; then
        echo
        info "Detected EFI partitions:"
        lsblk -ln -o NAME,FSTYPE,PARTLABEL "$DISK" | awk '$2=="vfat"'
        
        while true; do
            prompt_read EFI_PART "Select EFI partition to use (e.g., /dev/nvme0n1p1):"
            [[ -b "$EFI_PART" && $(lsblk -no FSTYPE "$EFI_PART") == "vfat" ]] && break
            warn "Invalid EFI partition"
        done
    fi
else
    WIPE_DISK=true
fi

### Partitioning and Formatting Disk ###
if $WIPE_DISK; then
    prompt_read EFI_SIZE "EFI size in MiB (default 2048):"
    EFI_SIZE=${EFI_SIZE:-2048}
    
    prompt_read ROOT_SIZE "Root size in GiB (0 = use remaining space):"
    ROOT_SIZE=${ROOT_SIZE:-0}
    
    warn "Wiping $DISK"
    prompt_read CONFIRM "Type '$DISK' to confirm:"
    [[ "$CONFIRM" == "$DISK" ]] || die "Disk wipe aborted"
    
    sgdisk --zap-all "$DISK"
    sgdisk -o "$DISK"
    
    if $UEFI; then
        warn "Creating EFI partition"
        sgdisk -n 1:0:+${EFI_SIZE}M -t 1:ef00 -c 1:EFI "$DISK"
        EFI_PART="/dev/$(lsblk -ln -o NAME "$DISK" | head -n 1)"
        mkfs.fat -F32 "$EFI_PART"
    fi
else
    prompt_read ROOT_SIZE "Root size in GiB (0 = use remaining space):"
    ROOT_SIZE=${ROOT_SIZE:-0}
fi

### Creating new encrypted root partition ###
warn "Creating LUKS encrypted root partition"

if [[ "$ROOT_SIZE" == "0" ]]; then
    sgdisk -n 0:0:0 -t 0:8300 -c 0:ROOT "$DISK"
else
    sgdisk -n 0:0:+${ROOT_SIZE}G -t 0:8300 -c 0:ROOT "$DISK"
fi

ROOT_PART="/dev/$(lsblk -ln -o NAME "$DISK" | tail -n 1)"

echo -n "$LUKS_PASSWORD" | cryptsetup luksFormat "$ROOT_PART" --type luks2 --key-file=-
echo -n "$LUKS_PASSWORD" | cryptsetup open "$ROOT_PART" cryptroot -
mkfs.btrfs /dev/mapper/cryptroot

### Mounting & Creating Subvolumes ###
mount /dev/mapper/cryptroot /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
umount /mnt

MOUNT_OPTS="noatime,compress=zstd,ssd,space_cache=v2,commit=120"
mount -o $MOUNT_OPTS,subvol=@ /dev/mapper/cryptroot /mnt
mkdir -p /mnt/home
mount -o $MOUNT_OPTS,subvol=@home /dev/mapper/cryptroot /mnt/home

if $UEFI; then
    mkdir -p /mnt/boot
    mount "$EFI_PART" /mnt/boot
fi

### Updating Mirrors & chroot ###
info "Installing base system..."
pacstrap /mnt base linux linux-firmware btrfs-progs cryptsetup sudo amd-ucode
#intet-ucode

info "Updating mirrors..."
pacman -Sy --noconfirm reflector archlinux-keyring
reflector --age 12 --protocol https --sort rate --save /mnt/etc/pacman.d/mirrorlist || warn "Reflector failed, continuing with default mirrorlist"

info "Copying post-install scripts..."
cp lib/ui.sh /mnt/root/ui.sh
cp chroot.sh /mnt/root/chroot.sh
chmod +x /mnt/root/chroot.sh

genfstab -U /mnt >> /mnt/etc/fstab

info "Entering chroot..."
arch-chroot /mnt /usr/bin/env \
DISK="$DISK" \
TIMEZONE="$TIMEZONE" \
LOCALE="$LOCALE" \
HOSTNAME="$HOSTNAME" \
USERNAME="$USERNAME" \
USER_PASSWORD="$USER_PASSWORD" \
ROOT_PASSWORD="$ROOT_PASSWORD" \
LUKS_PASSWORD="$LUKS_PASSWORD" \
EFI_PART="$EFI_PART" \
ROOT_PART="$ROOT_PART" \
UEFI="$UEFI" \
/root/chroot.sh

# Cleaning up ###
unset USER_PASSWORD ROOT_PASSWORD LUKS_PASSWORD

ok "Installation complete! You can reboot now."
