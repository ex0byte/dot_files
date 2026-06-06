#!/usr/bin/env bash
# =============================================================================
#  arch-backup.sh — Full Arch Linux Developer Environment Backup
#  Usage: bash arch-backup.sh [output-dir]
#  Default output dir: ~/arch-backup-<date>
# =============================================================================

set -euo pipefail

# ── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log()  { echo -e "${GREEN}[✔]${RESET} $*"; }
info() { echo -e "${CYAN}[➜]${RESET} $*"; }
warn() { echo -e "${YELLOW}[!]${RESET} $*"; }
fail() { echo -e "${RED}[✘]${RESET} $*"; exit 1; }
section() { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════${RESET}"; \
            echo -e "${BOLD}  $*${RESET}"; \
            echo -e "${BOLD}${CYAN}══════════════════════════════════════${RESET}"; }

# ── Destination ──────────────────────────────────────────────────────────────
DATE=$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_DIR="${1:-$HOME/arch-backup-$DATE}"
mkdir -p "$BACKUP_DIR"

info "Backup destination: ${BOLD}$BACKUP_DIR${RESET}"

# ── 1. Package Lists ──────────────────────────────────────────────────────────
section "1 · Package Lists"

PKG_DIR="$BACKUP_DIR/packages"
mkdir -p "$PKG_DIR"

info "Saving explicitly installed pacman packages..."
pacman -Qe > "$PKG_DIR/pacman-explicit.txt"
log "pacman-explicit.txt"

info "Saving ALL installed pacman packages (for reference)..."
pacman -Q > "$PKG_DIR/pacman-all.txt"
log "pacman-all.txt"

info "Saving native (non-AUR) explicit packages..."
pacman -Qen > "$PKG_DIR/pacman-native.txt"
log "pacman-native.txt"

info "Saving foreign (AUR/manual) packages..."
pacman -Qem > "$PKG_DIR/pacman-foreign.txt"
log "pacman-foreign.txt"

if command -v yay &>/dev/null; then
    info "Saving yay AUR package list..."
    yay -Qm > "$PKG_DIR/yay-aur.txt"
    log "yay-aur.txt"
else
    warn "yay not found — skipping AUR list"
fi

if command -v flatpak &>/dev/null; then
    info "Saving Flatpak apps..."
    flatpak list --app --columns=application > "$PKG_DIR/flatpak-apps.txt"
    log "flatpak-apps.txt"
fi

if command -v snap &>/dev/null; then
    info "Saving Snap packages..."
    snap list > "$PKG_DIR/snap-packages.txt"
    log "snap-packages.txt"
fi

# ── 2. Dotfiles & Config ──────────────────────────────────────────────────────
section "2 · Dotfiles & Config"

CFG_DIR="$BACKUP_DIR/config"
mkdir -p "$CFG_DIR"

# Shell configs
for f in .bashrc .bash_profile .zshrc .zsh_history .profile .inputrc .aliases; do
    [[ -f "$HOME/$f" ]] && { cp "$HOME/$f" "$CFG_DIR/"; log "~/$f"; }
done

# Fish
[[ -d "$HOME/.config/fish" ]] && { cp -r "$HOME/.config/fish" "$CFG_DIR/fish"; log "~/.config/fish"; }

# Git
[[ -f "$HOME/.gitconfig" ]] && { cp "$HOME/.gitconfig" "$CFG_DIR/.gitconfig"; log "~/.gitconfig"; }
[[ -f "$HOME/.gitignore_global" ]] && { cp "$HOME/.gitignore_global" "$CFG_DIR/.gitignore_global"; log "~/.gitignore_global"; }

# SSH (keys + config, NOT private keys — you can uncomment if needed)
if [[ -d "$HOME/.ssh" ]]; then
    mkdir -p "$CFG_DIR/ssh"
    [[ -f "$HOME/.ssh/config" ]] && cp "$HOME/.ssh/config" "$CFG_DIR/ssh/config"
    # Uncomment to include keys (store this backup safely!):
    # cp "$HOME/.ssh/id_"* "$CFG_DIR/ssh/" 2>/dev/null || true
    log "~/.ssh/config"
fi

# GPG pubkeys
if command -v gpg &>/dev/null; then
    gpg --export --armor > "$CFG_DIR/gpg-pubkeys.asc" 2>/dev/null
    log "GPG public keys"
fi

# Vim / Neovim
[[ -f "$HOME/.vimrc" ]] && { cp "$HOME/.vimrc" "$CFG_DIR/.vimrc"; log "~/.vimrc"; }
[[ -d "$HOME/.config/nvim" ]] && { cp -r "$HOME/.config/nvim" "$CFG_DIR/nvim"; log "~/.config/nvim"; }

# VS Code
if [[ -d "$HOME/.config/Code/User" ]]; then
    mkdir -p "$CFG_DIR/vscode"
    cp "$HOME/.config/Code/User/settings.json" "$CFG_DIR/vscode/" 2>/dev/null || true
    cp "$HOME/.config/Code/User/keybindings.json" "$CFG_DIR/vscode/" 2>/dev/null || true
    [[ -d "$HOME/.config/Code/User/snippets" ]] && \
        cp -r "$HOME/.config/Code/User/snippets" "$CFG_DIR/vscode/snippets"
    log "VS Code settings"
    # VS Code extensions
    if command -v code &>/dev/null; then
        code --list-extensions > "$CFG_DIR/vscode/extensions.txt"
        log "VS Code extensions list"
    fi
fi

# Alacritty / Kitty / WezTerm
for term in alacritty kitty wezterm; do
    [[ -d "$HOME/.config/$term" ]] && { cp -r "$HOME/.config/$term" "$CFG_DIR/$term"; log "~/.config/$term"; }
done

# tmux
[[ -f "$HOME/.tmux.conf" ]] && { cp "$HOME/.tmux.conf" "$CFG_DIR/.tmux.conf"; log "~/.tmux.conf"; }

# Htop
[[ -d "$HOME/.config/htop" ]] && { cp -r "$HOME/.config/htop" "$CFG_DIR/htop"; log "~/.config/htop"; }

# Starship prompt
[[ -f "$HOME/.config/starship.toml" ]] && { cp "$HOME/.config/starship.toml" "$CFG_DIR/starship.toml"; log "~/.config/starship.toml"; }

# Fonts (user-installed)
if [[ -d "$HOME/.local/share/fonts" ]]; then
    cp -r "$HOME/.local/share/fonts" "$CFG_DIR/fonts"
    log "~/.local/share/fonts"
fi

# Dunst / Rofi / Polybar / Waybar
for tool in dunst rofi polybar waybar picom; do
    [[ -d "$HOME/.config/$tool" ]] && { cp -r "$HOME/.config/$tool" "$CFG_DIR/$tool"; log "~/.config/$tool"; }
done

# GTK themes
[[ -f "$HOME/.config/gtk-3.0/settings.ini" ]] && {
    mkdir -p "$CFG_DIR/gtk-3.0"
    cp "$HOME/.config/gtk-3.0/settings.ini" "$CFG_DIR/gtk-3.0/"
    log "GTK-3 settings"
}
[[ -f "$HOME/.gtkrc-2.0" ]] && { cp "$HOME/.gtkrc-2.0" "$CFG_DIR/.gtkrc-2.0"; log ".gtkrc-2.0"; }

# ── 3. GNOME Extensions & Settings ──────────────────────────────────────────
section "3 · GNOME Extensions & Settings"

GNOME_DIR="$BACKUP_DIR/gnome"
mkdir -p "$GNOME_DIR"

if command -v gnome-extensions &>/dev/null; then
    info "Listing installed GNOME extensions..."
    gnome-extensions list > "$GNOME_DIR/extensions-list.txt"
    gnome-extensions list --enabled > "$GNOME_DIR/extensions-enabled.txt"
    log "Extension lists saved"

    info "Copying extension files..."
    EXT_SRC="$HOME/.local/share/gnome-shell/extensions"
    if [[ -d "$EXT_SRC" ]]; then
        cp -r "$EXT_SRC" "$GNOME_DIR/extensions"
        log "Extension files copied"
    fi

    info "Dumping GNOME dconf settings..."
    dconf dump / > "$GNOME_DIR/dconf-full.conf"
    dconf dump /org/gnome/shell/extensions/ > "$GNOME_DIR/dconf-extensions.conf"
    dconf dump /org/gnome/desktop/ > "$GNOME_DIR/dconf-desktop.conf"
    dconf dump /org/gnome/terminal/ > "$GNOME_DIR/dconf-terminal.conf" 2>/dev/null || true
    log "dconf dumps saved"
else
    warn "GNOME not detected — skipping GNOME section"
fi

# ── 4. Development Tools & Runtimes ─────────────────────────────────────────
section "4 · Dev Runtimes & Package Managers"

DEV_DIR="$BACKUP_DIR/dev"
mkdir -p "$DEV_DIR"

# Node.js / npm global packages
if command -v npm &>/dev/null; then
    npm list -g --depth=0 --json > "$DEV_DIR/npm-global.json" 2>/dev/null || \
    npm list -g --depth=0 > "$DEV_DIR/npm-global.txt" 2>/dev/null || true
    log "npm global packages"
fi

# nvm
[[ -d "$HOME/.nvm" ]] && {
    node --version > "$DEV_DIR/node-version.txt" 2>/dev/null || true
    npm --version >> "$DEV_DIR/node-version.txt" 2>/dev/null || true
    log "Node/npm versions"
}

# pnpm
if command -v pnpm &>/dev/null; then
    pnpm list -g > "$DEV_DIR/pnpm-global.txt" 2>/dev/null || true
    log "pnpm global packages"
fi

# Python pip
if command -v pip &>/dev/null; then
    pip list --format=freeze > "$DEV_DIR/pip-packages.txt" 2>/dev/null || true
    log "pip packages"
fi
if command -v pip3 &>/dev/null; then
    pip3 list --format=freeze > "$DEV_DIR/pip3-packages.txt" 2>/dev/null || true
fi

# Python pyenv
[[ -d "$HOME/.pyenv" ]] && {
    pyenv versions > "$DEV_DIR/pyenv-versions.txt" 2>/dev/null || true
    log "pyenv versions"
}

# Rust / cargo
if command -v cargo &>/dev/null; then
    cargo install --list > "$DEV_DIR/cargo-packages.txt" 2>/dev/null || true
    log "cargo packages"
fi

# Go
command -v go &>/dev/null && go version > "$DEV_DIR/go-version.txt" 2>/dev/null || true

# Ruby gems
if command -v gem &>/dev/null; then
    gem list > "$DEV_DIR/gems.txt" 2>/dev/null || true
    log "Ruby gems"
fi

# Docker
if command -v docker &>/dev/null; then
    docker images --format "{{.Repository}}:{{.Tag}}" > "$DEV_DIR/docker-images.txt" 2>/dev/null || true
    log "Docker image list"
fi

# Neovim / vim plugins (common plugin dirs)
for d in "$HOME/.vim/bundle" "$HOME/.local/share/nvim/site/pack"; do
    [[ -d "$d" ]] && {
        ls "$d" > "$DEV_DIR/vim-plugins.txt" 2>/dev/null || true
        log "Vim plugin list"
    }
done

# ── 5. Cron Jobs ─────────────────────────────────────────────────────────────
section "5 · Cron & Systemd User Services"

MISC_DIR="$BACKUP_DIR/misc"
mkdir -p "$MISC_DIR"

crontab -l > "$MISC_DIR/crontab.txt" 2>/dev/null && log "crontab" || warn "No crontab found"

# Systemd user services
if [[ -d "$HOME/.config/systemd/user" ]]; then
    cp -r "$HOME/.config/systemd/user" "$MISC_DIR/systemd-user"
    log "systemd user services"
fi

# ── 6. Browser Profiles ───────────────────────────────────────────────────────
section "6 · Browser Bookmarks"

BROWSER_DIR="$BACKUP_DIR/browsers"
mkdir -p "$BROWSER_DIR"

# Firefox bookmarks (note: backup backup.jsonlz4 files)
FF_PROFILES=$(find "$HOME/.mozilla/firefox" -name "places.sqlite" 2>/dev/null | head -5)
if [[ -n "$FF_PROFILES" ]]; then
    mkdir -p "$BROWSER_DIR/firefox"
    while IFS= read -r db; do
        prof_dir=$(dirname "$db")
        prof_name=$(basename "$prof_dir")
        cp "$db" "$BROWSER_DIR/firefox/${prof_name}-places.sqlite"
    done <<< "$FF_PROFILES"
    log "Firefox bookmarks (places.sqlite)"
fi

# Chrome / Chromium bookmarks
for browser_dir in "$HOME/.config/google-chrome" "$HOME/.config/chromium" "$HOME/.config/brave-browser"; do
    bname=$(basename "$browser_dir")
    BOOKMARKS=$(find "$browser_dir" -name "Bookmarks" 2>/dev/null | head -3)
    if [[ -n "$BOOKMARKS" ]]; then
        mkdir -p "$BROWSER_DIR/$bname"
        cp $BOOKMARKS "$BROWSER_DIR/$bname/" 2>/dev/null || true
        log "$bname bookmarks"
    fi
done

# ── 7. Hosts & Network ────────────────────────────────────────────────────────
section "7 · Hosts & Network"

[[ -f "/etc/hosts" ]] && { cp /etc/hosts "$MISC_DIR/hosts"; log "/etc/hosts"; }
[[ -d "$HOME/.config/networkmanager" ]] && {
    cp -r "$HOME/.config/networkmanager" "$MISC_DIR/networkmanager" 2>/dev/null || true
}

# ── 8. Create Archive ─────────────────────────────────────────────────────────
section "8 · Compressing Backup"

ARCHIVE="$HOME/arch-backup-$DATE.tar.gz"
info "Creating archive at $ARCHIVE ..."
tar -czf "$ARCHIVE" -C "$(dirname "$BACKUP_DIR")" "$(basename "$BACKUP_DIR")"
log "Archive created: $ARCHIVE"

# Checksum
sha256sum "$ARCHIVE" > "${ARCHIVE}.sha256"
log "SHA256: ${ARCHIVE}.sha256"

# ── Done ──────────────────────────────────────────────────────────────────────
section "Backup Complete"
echo -e "${GREEN}${BOLD}"
echo "  Archive : $ARCHIVE"
echo "  Size    : $(du -sh "$ARCHIVE" | cut -f1)"
echo "  Verify  : sha256sum -c ${ARCHIVE}.sha256"
echo -e "${RESET}"
echo -e "${YELLOW}⚠  Store this archive on an external drive or cloud storage before formatting!${RESET}\n"