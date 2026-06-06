#!/usr/bin/env bash
set -e
source "$(dirname "$0")/lib/ui.sh"

USERNAME="$(whoami)"
USER_HOME="/home/$USERNAME"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DOTFILES_DIR="$REPO_DIR/dotfiles"

info "Starting selective dotfiles backup..."
info "User: $USERNAME"
info "Repo: $DOTFILES_DIR"

mkdir -p \
    "$DOTFILES_DIR/config" \
    "$DOTFILES_DIR/home" \
    "$DOTFILES_DIR/gnome" \
    "$DOTFILES_DIR/apps" \
    "$DOTFILES_DIR/icons" \
    "$DOTFILES_DIR/extensions"

CONFIG_DIRS=(
    nvim
    gtk-4.0
    gnome-shell
)

### Package lists ###
info "Backing up pacman packages..."
pacman -Qqe > "$DOTFILES_DIR/apps/pacman.txt"
ok "Pacman package list saved"

info "Backing up AUR packages..."
pacman -Qqm > "$DOTFILES_DIR/apps/aur.txt"
ok "AUR package list saved"

### ~/.config directories ###
info "Backing up selected ~/.config directories..."
for dir in "${CONFIG_DIRS[@]}"; do
    if [[ -d "$USER_HOME/.config/$dir" ]]; then
        rsync -a --delete \
            "$USER_HOME/.config/$dir/" \
            "$DOTFILES_DIR/config/$dir/"
        ok "Backed up ~/.config/$dir"
    else
        warn "~/.config/$dir not found, skipping"
    fi
done

### Home dotfiles ###
HOME_FILES=(
    .bashrc
)

info "Backing up home dotfiles..."
for file in "${HOME_FILES[@]}"; do
    if [[ -f "$USER_HOME/$file" ]]; then
        cp "$USER_HOME/$file" "$DOTFILES_DIR/home/"
        ok "Backed up $file"
    else
        warn "$file not found, skipping"
    fi
done

### Icons ###
info "Backing up icons..."
if [[ -d "$USER_HOME/.icons" ]]; then
    rsync -a --delete "$USER_HOME/.icons/" "$DOTFILES_DIR/icons/"
    ok "Icons backed up"
else
    warn "~/.icons not found, skipping"
fi

### GNOME Shell extensions ###
EXT_SRC="$USER_HOME/.local/share/gnome-shell/extensions"
EXT_DST="$DOTFILES_DIR/extensions"

info "Backing up GNOME Shell extensions..."
if [[ -d "$EXT_SRC" && "$(ls -A "$EXT_SRC")" ]]; then
    rsync -a --delete "$EXT_SRC/" "$EXT_DST/"
    ok "GNOME extensions backed up"
else
    warn "No user GNOME extensions found"
fi

### dconf ###
info "Backing up GNOME dconf settings..."
dconf dump / > "$DOTFILES_DIR/gnome/dconf.ini"
ok "GNOME settings backed up"

ok "Backup complete."