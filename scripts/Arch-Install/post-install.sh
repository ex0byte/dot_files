#!/usr/bin/env bash
set -e
source "./lib/ui.sh"

USERNAME="$(whoami)"
USER_HOME="/home/$USERNAME"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DOTFILES_DIR="$REPO_DIR/dotfiles"

info "Starting post-install restoration..."
info "User: $USERNAME"
info "Repo: $DOTFILES_DIR"

if [[ -f "$DOTFILES_DIR/apps/pacman.txt" ]]; then
    info "Installing pacman packages..."
    sudo pacman -S --noconfirm - < "$DOTFILES_DIR/apps/pacman.txt"
    ok "Pacman packages installed"
fi

if [[ -f "$DOTFILES_DIR/apps/aur.txt" ]]; then
    if ! command -v yay &>/dev/null; then
        info "Installing yay..."
        sudo pacman -S --noconfirm git base-devel
        git clone https://aur.archlinux.org/yay.git /tmp/yay
        (cd /tmp/yay && makepkg -si --noconfirm)
        rm -rf /tmp/yay
        ok "yay installed"
    fi
    
    info "Installing AUR packages..."
    yay -S --noconfirm - < "$DOTFILES_DIR/apps/aur.txt"
    ok "AUR packages installed"
fi

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
        ok "Restored $dir"
    fi
done

info "Restoring icons..."
if[[ -d "$DOTFILES_DIR/icons"]];then
    if[[ -d "$USER_HOME/.icons/"]]; then
        continue;
    else
        (cd $USER_HOME; mkdir .icons);
    fi
    cp -r "$DOTFILES_DIR/icons" "$USER_HOME/.icons/";
fi
ok "Restored icons";

HOME_FILES=(
    .bashrc
    .gitconfig
)

info "Restoring home dotfiles..."
for file in "${HOME_FILES[@]}"; do
    if [[ -f "$DOTFILES_DIR/home/$file" ]]; then
        cp "$DOTFILES_DIR/home/$file" "$USER_HOME/$file"
        ok "Restored $file"
    fi
done

if [[ -f "$DOTFILES_DIR/gnome/dconf.ini" ]]; then
    info "Restoring Gnome settings..."
    dconf load / < "$DOTFILES_DIR/gnome/dconf.ini"
    ok "Gnome settings restored"
fi

sudo chown -R "$USERNAME:$USERNAME" "$USER_HOME/.config" "$USER_HOME/.local" "$USER_HOME"/* 2>/dev/null || true



EXT_SRC="$DOTFILES_DIR/extensions"
EXT_DST="$USER_HOME/.local/share/gnome-shell/extensions"

info "Restoring Gnome Shell extensions..."

if [[ -d "$EXT_SRC" && "$(ls -A "$EXT_SRC")" ]]; then
    mkdir -p "$EXT_DST"
    rsync -a "$EXT_SRC/" "$EXT_DST/"
    ok "Gnome extensions restored"
else
    warn "No Gnome extensions to restore"
fi

info "Enabling Gnome Shell extensions..."
for dir in "$EXT_DST"/*; do
    [[ -d "$dir" ]] || continue
    uuid="$(basename "$dir")"
    gnome-extensions enable "$uuid" || warn "Failed to enable $uuid"
done
ok "Extensions enabled"

ok "Post-install complete."
warn "Log out and log back in (or reboot) for all Gnome changes to apply"
