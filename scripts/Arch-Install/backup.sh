#!/usr/bin/env bash
set -e
source "./lib/ui.sh"

USERNAME="$(whoami)"
USER_HOME="/home/$USERNAME"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DOTFILES_DIR="$REPO_DIR/dotfiles"

info "Starting selective dotfiles backup..."
info "User: $USERNAME"
info "Repo: $DOTFILES_DIR"

mkdir -p "$DOTFILES_DIR/config" "$DOTFILES_DIR/home" "$DOTFILES_DIR/gnome"

CONFIG_DIRS=(
    nvim
    gtk-4.0
    gnome-shell
)

info "Backing up selected ~/.config directories..."
for dir in "${CONFIG_DIRS[@]}"; do
    if [[ -d "$USER_HOME/.config/$dir" ]]; then
        rsync -a --delete \
        "$USER_HOME/.config/$dir/" \
        "$DOTFILES_DIR/config/$dir/"
        ok "Backed up $dir"
    else
        warn "~/.config/$dir not found, skipping"
    fi
done

HOME_FILES=(
    .bashrc
    .bash_profile
    .gitconfig
)

info "Backing up icons"
if [[ -d "$USER_HOME/.icons" ]]; then
    cp -r "$USER_HOME/.icons" "$DOTFILES_DIR/icons/"
    ok "Backed up icons"
else
    warn "icons not found, skipping"
fi


# info "Backing up home dotfiles..."
# for file in "${HOME_FILES[@]}"; do
#     if [[ -f "$USER_HOME/$file" ]]; then
#         cp "$USER_HOME/$file" "$DOTFILES_DIR/home/"
#         ok "Backed up $file"
#     else
#         warn "$file not found, skipping"
#     fi
# done
info "Backing up home dotfiles..."
for file in "${HOME_FILES[@]}"; do
    if [[ -f "$USER_HOME/$file" ]]; then
        cp "$USER_HOME/$file" "$DOTFILES_DIR/home/"
        ok "Backed up $file"
    else
        warn "$file not found, skipping"
    fi
done


EXT_SRC="$USER_HOME/.local/share/gnome-shell/extensions"
EXT_DST="$DOTFILES_DIR/extensions"

info "Backing up Gnome Shell extensions..."

mkdir -p "$EXT_DST"

if [[ -d "$EXT_SRC" && "$(ls -A "$EXT_SRC")" ]]; then
    rsync -a --delete "$EXT_SRC/" "$EXT_DST/"
    ok "Gnome extensions backed up"
else
    warn "No user Gnome extensions found"
fi


info "Backing up Gnome dconf..."
dconf dump / > "$DOTFILES_DIR/gnome/dconf.ini"
ok "Gnome settings backed up"

ok "Backup complete."
