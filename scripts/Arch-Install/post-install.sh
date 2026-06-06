#!/usr/bin/env bash
set -e
source "$(dirname "$0")/lib/ui.sh"

USERNAME="$(whoami)"
USER_HOME="/home/$USERNAME"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DOTFILES_DIR="$REPO_DIR/dotfiles"

info "Starting post-install restoration..."
info "User: $USERNAME"
info "Repo: $DOTFILES_DIR"

### Pacman packages ###
if [[ -f "$DOTFILES_DIR/apps/pacman.txt" ]]; then
    info "Installing pacman packages..."
    sudo pacman -S --needed --noconfirm - < "$DOTFILES_DIR/apps/pacman.txt"
    ok "Pacman packages installed"
fi

### AUR packages ###
if [[ -f "$DOTFILES_DIR/apps/aur.txt" ]]; then
    if ! command -v yay &>/dev/null; then
        info "Installing yay (AUR helper)..."
        sudo pacman -S --needed --noconfirm git base-devel
        git clone https://aur.archlinux.org/yay.git /tmp/yay
        (cd /tmp/yay && makepkg -si --noconfirm)
        rm -rf /tmp/yay
        ok "yay installed"
    fi

    info "Installing AUR packages..."
    yay -S --needed --noconfirm - < "$DOTFILES_DIR/apps/aur.txt"
    ok "AUR packages installed"
fi

### ~/.config directories ###
CONFIG_DIRS=(
    nvim
    gtk-4.0
    gnome-shell
)

info "Restoring ~/.config directories..."
mkdir -p "$USER_HOME/.config"
for dir in "${CONFIG_DIRS[@]}"; do
    if [[ -d "$DOTFILES_DIR/config/$dir" ]]; then
        rsync -a \
            "$DOTFILES_DIR/config/$dir/" \
            "$USER_HOME/.config/$dir/"
        ok "Restored ~/.config/$dir"
    else
        warn "No backup for ~/.config/$dir, skipping"
    fi
done

### Home dotfiles ###
HOME_FILES=(
    .bashrc
)

info "Restoring home dotfiles..."
for file in "${HOME_FILES[@]}"; do
    if [[ -f "$DOTFILES_DIR/home/$file" ]]; then
        cp "$DOTFILES_DIR/home/$file" "$USER_HOME/$file"
        ok "Restored $file"
    else
        warn "No backup for $file, skipping"
    fi
done

### Icons ###
info "Restoring icons..."
if [[ -d "$DOTFILES_DIR/icons" ]]; then
    mkdir -p "$USER_HOME/.icons"
    rsync -a "$DOTFILES_DIR/icons/" "$USER_HOME/.icons/"
    ok "Icons restored"
else
    warn "No icons backup found, skipping"
fi

### GNOME dconf settings ###
if [[ -f "$DOTFILES_DIR/gnome/dconf.ini" ]]; then
    info "Restoring GNOME dconf settings..."
    mkdir -p "$DOTFILES_DIR/gnome"
    dconf load / < "$DOTFILES_DIR/gnome/dconf.ini"
    ok "GNOME settings restored"
fi

### GNOME Shell extensions ###
EXT_SRC="$DOTFILES_DIR/extensions"
EXT_DST="$USER_HOME/.local/share/gnome-shell/extensions"

info "Restoring GNOME Shell extensions..."
if [[ -d "$EXT_SRC" && "$(ls -A "$EXT_SRC")" ]]; then
    mkdir -p "$EXT_DST"
    rsync -a "$EXT_SRC/" "$EXT_DST/"
    ok "GNOME extensions restored"
else
    warn "No GNOME extensions backup found, skipping"
fi

info "Enabling GNOME Shell extensions..."
for dir in "$EXT_DST"/*; do
    [[ -d "$dir" ]] || continue
    uuid="$(basename "$dir")"
    gnome-extensions enable "$uuid" || warn "Failed to enable $uuid"
done
ok "Extensions enabled"

### Fix ownership for everything written above ###
info "Fixing file ownership..."
sudo chown -R "$USERNAME:$USERNAME" \
    "$USER_HOME/.config" \
    "$USER_HOME/.local" \
    "$USER_HOME/.icons" \
    "$USER_HOME/.bashrc" \
    2>/dev/null || true
ok "Ownership fixed"

ok "Post-install complete."
warn "Log out and log back in (or reboot) for all GNOME changes to take effect."