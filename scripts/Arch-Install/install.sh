#!/usr/bin/env bash
set -e
source "$(dirname "$0")/lib/ui.sh"

info "Starting Arch Installation......"

### Detecting UFEI/BIOS ###
if [[ -d /sys/firmware/efi/efivars ]]; then
    ok "UEFI system detected"
else
    die "This installer supports UEFI systems only.
    Reboot and select the UEFI boot option."
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

while true; do
    prompt_read_password USER_PASSWORD "User password:"
    prompt_read_password CONFIRM_PASSWORD "Confirm user password:"
    [[ "$USER_PASSWORD" == "$CONFIRM_PASSWORD" ]] && break
    fail "Passwords do not match"
done
ok "User password set"

while true; do
    prompt_read_password ROOT_PASSWORD "Root password:"
    prompt_read_password CONFIRM_ROOT "Confirm root password:"
    [[ "$ROOT_PASSWORD" == "$CONFIRM_ROOT" ]] && break
    fail "Root passwords do not match"
done
ok "Root password set"

while true; do
    prompt_read_password LUKS_PASSWORD "Enter LUKS passphrase for root:"
    prompt_read_password CONFIRM_LUKS "Confirm LUKS passphrase:"
    [[ "$LUKS_PASSWORD" == "$CONFIRM_LUKS" ]] && break
    fail "LUKS passphrases do not match"
done
ok "LUKS passphrase set"

### Confirmation ###
echo
warn "Please confirm the settings below:"
echo "Disk:     $DISK"
warn "ALL DATA ON $DISK WILL BE ERASED IF YOU CHOOSE WIPE"
echo "Hostname: $HOSTNAME"
echo "Username: $USERNAME"

confirm "Proceed with installation" || die "Installation aborted"
ok "Proceeding with installation"

timedatectl set-ntp true

### Partitioning, Filesystem and LUKS ###
warn "Manually partition the disk using fdisk."
if $UEFI; then
    info "Required layout:"
    info "  1) EFI System Partition (FAT32, type EFI)"
    info "  2) Root partition (Linux filesystem, for LUKS)"
fi

read -rp "Press ENTER to launch fdisk on $DISK..." _
fdisk "$DISK"

info "Reloading partition table..."
partprobe "$DISK"
sleep 2

info "Current partition layout:"
lsblk -o NAME,SIZE,FSTYPE,TYPE,MOUNTPOINT "$DISK"

### Select EFI partition
while true; do
    prompt_read EFI_PART "EFI partition (e.g. /dev/nvme0n1p1):"
    [[ -b "$EFI_PART" ]] || continue
    
    if [[ "$(blkid -o value -s TYPE "$EFI_PART")" != "vfat" ]]; then
        warn "Formatting EFI partition as FAT32"
        mkfs.fat -F32 "$EFI_PART"
    fi
    break
done

### Select ROOT partition
while true; do
    prompt_read ROOT_PART "Root partition for LUKS (e.g. /dev/nvme0n1p2):"
    [[ -b "$ROOT_PART" ]] && break
done

### LUKS setup ###
if ! cryptsetup isLuks "$ROOT_PART"; then
    info "Creating LUKS container on $ROOT_PART"
    echo -n "$LUKS_PASSWORD" | cryptsetup luksFormat "$ROOT_PART" --type luks2 --key-file=-
else
    info "LUKS already exists on $ROOT_PART"
fi

if ! cryptsetup status cryptroot &>/dev/null; then
    info "Opening LUKS container"
    echo -n "$LUKS_PASSWORD" | cryptsetup open "$ROOT_PART" cryptroot --key-file=-
else
    info "LUKS container already opened"
fi


### BTRFS filesystem ###
if ! blkid /dev/mapper/cryptroot | grep -q btrfs; then
    info "Creating BTRFS filesystem"
    mkfs.btrfs /dev/mapper/cryptroot
else
    info "BTRFS filesystem already exists"
fi


### Create subvolumes ###
mount -o subvolid=5 /dev/mapper/cryptroot /mnt
for subvol in @ @home; do
    if ! btrfs subvolume show "/mnt/$subvol" &>/dev/null; then
        info "Creating subvolume $subvol"
        btrfs subvolume create "/mnt/$subvol"
    else
        info "Subvolume $subvol already exists"
    fi
done
umount /mnt

### Mount final layout ###

MOUNT_OPTS="noatime,compress=zstd,ssd,space_cache=v2,commit=120"

mount -o "$MOUNT_OPTS,subvol=@" /dev/mapper/cryptroot /mnt
mkdir -p /mnt/home
mount -o "$MOUNT_OPTS,subvol=@home" /dev/mapper/cryptroot /mnt/home

mkdir -p /mnt/boot
mount "$EFI_PART" /mnt/boot || die "Failed to mount EFI partition at /mnt/boot"
mountpoint -q /mnt/boot || die "EFI partition not mounted"
ok "EFI partition mounted at /mnt/boot"

### Base system & chroot
info "Installing base system..."
pacstrap /mnt base linux linux-firmware btrfs-progs cryptsetup sudo archlinux-keyring amd-ucode

info "Copying post-install scripts..."
cp lib/ui.sh /mnt/root/ui.sh
cp chroot.sh /mnt/root/chroot.sh
chmod +x /mnt/root/chroot.sh

genfstab -U /mnt >> /mnt/etc/fstab

info "Entering chroot..."
arch-chroot /mnt /usr/bin/env \
TIMEZONE="$TIMEZONE" \
LOCALE="$LOCALE" \
HOSTNAME="$HOSTNAME" \
USERNAME="$USERNAME" \
USER_PASSWORD="$USER_PASSWORD" \
ROOT_PASSWORD="$ROOT_PASSWORD" \
ROOT_PART="$ROOT_PART" \
/root/chroot.sh

### Cleaning up ###
unset USER_PASSWORD ROOT_PASSWORD LUKS_PASSWORD

ok "Installation complete! You can reboot now."