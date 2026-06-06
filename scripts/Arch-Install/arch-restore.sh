#!/usr/bin/env bash
# =============================================================================
#  arch-restore.sh — Full Arch Linux Developer Environment Restore
#  Usage: bash arch-restore.sh <backup-dir-or-archive.tar.gz>
#  Run this AFTER a fresh Arch install with base-devel, git, and internet.
# =============================================================================

set -euo pipefail

# ── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log()  { echo -e "${GREEN}[✔]${RESET} $*"; }
info() { echo -e "${CYAN}[➜]${RESET} $*"; }
warn() { echo -e "${YELLOW}[!]${RESET} $*"; }
fail() { echo -e "${RED}[✘]${RESET} $*"; exit 1; }
skip() { echo -e "${YELLOW}[~]${RESET} Skipping: $*"; }
section() { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════${RESET}"; \
            echo -e "${BOLD}  $*${RESET}"; \
            echo -e "${BOLD}${CYAN}══════════════════════════════════════${RESET}"; }

prompt_continue() {
    echo -e "\n${YELLOW}Press [Enter] to continue or Ctrl+C to abort...${RESET}"
    read -r
}

# ── Args & Extract ────────────────────────────────────────────────────────────
[[ $# -lt 1 ]] && fail "Usage: bash arch-restore.sh <backup-dir-or-archive.tar.gz>"

INPUT="$1"
if [[ "$INPUT" == *.tar.gz ]]; then
    [[ ! -f "$INPUT" ]] && fail "Archive not found: $INPUT"
    info "Extracting archive..."
    BACKUP_DIR=$(mktemp -d /tmp/arch-restore-XXXXX)
    tar -xzf "$INPUT" -C "$BACKUP_DIR" --strip-components=1
    log "Extracted to $BACKUP_DIR"
else
    BACKUP_DIR="$INPUT"
    [[ ! -d "$BACKUP_DIR" ]] && fail "Backup directory not found: $BACKUP_DIR"
fi

section "Arch Linux Restore Starting"
echo -e "  Backup source : ${BOLD}$BACKUP_DIR${RESET}"
echo -e "  Target user   : ${BOLD}$USER${RESET} (HOME=$HOME)"
prompt_continue

# ── 1. System Update ──────────────────────────────────────────────────────────
section "1 · System Update"
info "Syncing and updating pacman..."
sudo pacman -Syu --noconfirm
log "System updated"

# ── 2. Install yay (AUR helper) ───────────────────────────────────────────────
section "2 · AUR Helper (yay)"

if ! command -v yay &>/dev/null; then
    info "Installing yay..."
    sudo pacman -S --noconfirm --needed git base-devel
    TMP_YAY=$(mktemp -d)
    git clone https://aur.archlinux.org/yay.git "$TMP_YAY"
    (cd "$TMP_YAY" && makepkg -si --noconfirm)
    rm -rf "$TMP_YAY"
    log "yay installed"
else
    log "yay already installed"
fi

# ── 3. Restore Pacman Native Packages ────────────────────────────────────────
section "3 · Pacman Native Packages"

PKG_DIR="$BACKUP_DIR/packages"

if [[ -f "$PKG_DIR/pacman-native.txt" ]]; then
    info "Reading native package list..."
    # Extract just package names (strip versions)
    PKGS=$(awk '{print $1}' "$PKG_DIR/pacman-native.txt" | tr '\n' ' ')
    info "Installing $(echo "$PKGS" | wc -w) native packages..."
    # Install in batches, ignoring already-installed ones
    sudo pacman -S --noconfirm --needed $PKGS 2>&1 | grep -v "^warning: .* is up to date" || true
    log "Native packages restored"
else
    warn "pacman-native.txt not found — skipping"
fi

# ── 4. Restore AUR Packages ───────────────────────────────────────────────────
section "4 · AUR Packages (yay)"

AUR_FILE=""
[[ -f "$PKG_DIR/yay-aur.txt" ]] && AUR_FILE="$PKG_DIR/yay-aur.txt"
[[ -z "$AUR_FILE" && -f "$PKG_DIR/pacman-foreign.txt" ]] && AUR_FILE="$PKG_DIR/pacman-foreign.txt"

if [[ -n "$AUR_FILE" ]]; then
    info "Reading AUR package list from $AUR_FILE..."
    AUR_PKGS=$(awk '{print $1}' "$AUR_FILE" | tr '\n' ' ')
    info "Installing AUR packages..."
    yay -S --noconfirm --needed $AUR_PKGS 2>&1 || warn "Some AUR packages may have failed — check output"
    log "AUR packages restored"
else
    warn "No AUR package list found — skipping"
fi

# ── 5. Flatpak ────────────────────────────────────────────────────────────────
section "5 · Flatpak"

if [[ -f "$PKG_DIR/flatpak-apps.txt" ]]; then
    if ! command -v flatpak &>/dev/null; then
        sudo pacman -S --noconfirm flatpak
        flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    fi
    info "Restoring Flatpak apps..."
    while IFS= read -r app; do
        [[ -z "$app" ]] && continue
        flatpak install -y flathub "$app" 2>/dev/null || warn "Flatpak $app failed"
    done < "$PKG_DIR/flatpak-apps.txt"
    log "Flatpak apps restored"
fi

# ── 6. Restore Config Files ───────────────────────────────────────────────────
section "6 · Dotfiles & Config"

CFG_DIR="$BACKUP_DIR/config"

restore_file() {
    local src="$1" dst="$2"
    [[ -f "$src" ]] || return 0
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    log "Restored: $dst"
}

restore_dir() {
    local src="$1" dst="$2"
    [[ -d "$src" ]] || return 0
    mkdir -p "$(dirname "$dst")"
    cp -r "$src" "$dst"
    log "Restored dir: $dst"
}

# Shell configs
for f in .bashrc .bash_profile .zshrc .zsh_history .profile .inputrc .aliases; do
    restore_file "$CFG_DIR/$f" "$HOME/$f"
done

# Fish
restore_dir "$CFG_DIR/fish" "$HOME/.config/fish"

# Git
restore_file "$CFG_DIR/.gitconfig" "$HOME/.gitconfig"
restore_file "$CFG_DIR/.gitignore_global" "$HOME/.gitignore_global"

# SSH config (not keys)
if [[ -f "$CFG_DIR/ssh/config" ]]; then
    mkdir -p "$HOME/.ssh"
    cp "$CFG_DIR/ssh/config" "$HOME/.ssh/config"
    chmod 600 "$HOME/.ssh/config"
    log "Restored: ~/.ssh/config"
fi

# GPG keys
if [[ -f "$CFG_DIR/gpg-pubkeys.asc" ]]; then
    gpg --import "$CFG_DIR/gpg-pubkeys.asc" 2>/dev/null || true
    log "GPG public keys imported"
fi

# Vim / Neovim
restore_file "$CFG_DIR/.vimrc" "$HOME/.vimrc"
restore_dir "$CFG_DIR/nvim" "$HOME/.config/nvim"

# VS Code
if [[ -d "$CFG_DIR/vscode" ]]; then
    mkdir -p "$HOME/.config/Code/User"
    restore_file "$CFG_DIR/vscode/settings.json" "$HOME/.config/Code/User/settings.json"
    restore_file "$CFG_DIR/vscode/keybindings.json" "$HOME/.config/Code/User/keybindings.json"
    restore_dir "$CFG_DIR/vscode/snippets" "$HOME/.config/Code/User/snippets"

    if [[ -f "$CFG_DIR/vscode/extensions.txt" ]] && command -v code &>/dev/null; then
        info "Installing VS Code extensions..."
        while IFS= read -r ext; do
            [[ -z "$ext" ]] && continue
            code --install-extension "$ext" --force 2>/dev/null || warn "Extension failed: $ext"
        done < "$CFG_DIR/vscode/extensions.txt"
        log "VS Code extensions installed"
    fi
fi

# Terminal emulators
for term in alacritty kitty wezterm; do
    restore_dir "$CFG_DIR/$term" "$HOME/.config/$term"
done

# tmux / starship / htop
restore_file "$CFG_DIR/.tmux.conf" "$HOME/.tmux.conf"
restore_file "$CFG_DIR/starship.toml" "$HOME/.config/starship.toml"
restore_dir "$CFG_DIR/htop" "$HOME/.config/htop"

# Status bar / compositor
for tool in dunst rofi polybar waybar picom; do
    restore_dir "$CFG_DIR/$tool" "$HOME/.config/$tool"
done

# GTK
if [[ -d "$CFG_DIR/gtk-3.0" ]]; then
    mkdir -p "$HOME/.config/gtk-3.0"
    restore_file "$CFG_DIR/gtk-3.0/settings.ini" "$HOME/.config/gtk-3.0/settings.ini"
fi
restore_file "$CFG_DIR/.gtkrc-2.0" "$HOME/.gtkrc-2.0"

# Fonts
if [[ -d "$CFG_DIR/fonts" ]]; then
    mkdir -p "$HOME/.local/share/fonts"
    cp -r "$CFG_DIR/fonts/." "$HOME/.local/share/fonts/"
    fc-cache -fv "$HOME/.local/share/fonts" &>/dev/null
    log "Fonts restored and cache rebuilt"
fi

# ── 7. GNOME Extensions & Settings ──────────────────────────────────────────
section "7 · GNOME Extensions & Settings"

GNOME_DIR="$BACKUP_DIR/gnome"

if [[ -d "$GNOME_DIR" ]] && command -v gnome-extensions &>/dev/null; then

    # Copy extension files first
    if [[ -d "$GNOME_DIR/extensions" ]]; then
        mkdir -p "$HOME/.local/share/gnome-shell/extensions"
        cp -r "$GNOME_DIR/extensions/." "$HOME/.local/share/gnome-shell/extensions/"
        log "Extension files copied"
    fi

    # Enable extensions from the enabled list
    if [[ -f "$GNOME_DIR/extensions-enabled.txt" ]]; then
        info "Enabling GNOME extensions..."
        while IFS= read -r ext_uuid; do
            [[ -z "$ext_uuid" ]] && continue
            gnome-extensions enable "$ext_uuid" 2>/dev/null && log "Enabled: $ext_uuid" || \
                warn "Could not enable: $ext_uuid"
        done < "$GNOME_DIR/extensions-enabled.txt"
    fi

    # Restore dconf settings
    if [[ -f "$GNOME_DIR/dconf-extensions.conf" ]]; then
        info "Loading extension dconf settings..."
        dconf load /org/gnome/shell/extensions/ < "$GNOME_DIR/dconf-extensions.conf"
        log "Extension settings restored"
    fi

    if [[ -f "$GNOME_DIR/dconf-desktop.conf" ]]; then
        info "Loading desktop dconf settings..."
        dconf load /org/gnome/desktop/ < "$GNOME_DIR/dconf-desktop.conf"
        log "Desktop settings restored"
    fi

    if [[ -f "$GNOME_DIR/dconf-terminal.conf" ]]; then
        dconf load /org/gnome/terminal/ < "$GNOME_DIR/dconf-terminal.conf" 2>/dev/null || true
        log "Terminal settings restored"
    fi

    warn "Full dconf-full.conf is available at $GNOME_DIR/dconf-full.conf"
    warn "Run: dconf load / < $GNOME_DIR/dconf-full.conf  (to restore ALL gnome settings)"

else
    skip "GNOME not detected or no GNOME backup found"
fi

# ── 8. Dev Runtimes ───────────────────────────────────────────────────────────
section "8 · Dev Runtimes"

DEV_DIR="$BACKUP_DIR/dev"

# Install nvm if node version is recorded
if [[ -f "$DEV_DIR/node-version.txt" ]] && [[ ! -d "$HOME/.nvm" ]]; then
    info "Installing nvm..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    export NVM_DIR="$HOME/.nvm"
    source "$NVM_DIR/nvm.sh"
    NODE_VER=$(head -1 "$DEV_DIR/node-version.txt" | sed 's/v//')
    nvm install "$NODE_VER" || true
    log "nvm + Node.js installed"
fi

# npm global packages
if [[ -f "$DEV_DIR/npm-global.json" ]] && command -v npm &>/dev/null; then
    info "Installing npm global packages..."
    # Parse JSON and install
    python3 -c "
import json, subprocess, sys
with open('$DEV_DIR/npm-global.json') as f:
    data = json.load(f)
deps = data.get('dependencies', {})
for pkg in deps:
    if pkg != 'npm':
        subprocess.run(['npm', 'install', '-g', pkg], check=False)
" 2>/dev/null || warn "npm global restore needs python3 or manual install"
fi

# pip packages
if [[ -f "$DEV_DIR/pip3-packages.txt" ]] && command -v pip3 &>/dev/null; then
    info "Installing pip3 packages..."
    pip3 install -r "$DEV_DIR/pip3-packages.txt" 2>/dev/null || warn "Some pip packages failed"
    log "pip3 packages installed"
fi

# Rust / cargo
if [[ -f "$DEV_DIR/cargo-packages.txt" ]]; then
    if ! command -v cargo &>/dev/null; then
        info "Installing Rust via rustup..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source "$HOME/.cargo/env"
    fi
    info "Installing cargo packages..."
    grep -oP '^\S+(?= v)' "$DEV_DIR/cargo-packages.txt" | while read -r pkg; do
        cargo install "$pkg" 2>/dev/null || warn "cargo install $pkg failed"
    done
    log "Cargo packages installed"
fi

# ── 9. Cron & Systemd ─────────────────────────────────────────────────────────
section "9 · Cron & Systemd User Services"

MISC_DIR="$BACKUP_DIR/misc"

if [[ -f "$MISC_DIR/crontab.txt" ]]; then
    LINES=$(wc -l < "$MISC_DIR/crontab.txt")
    if [[ "$LINES" -gt 0 ]]; then
        crontab "$MISC_DIR/crontab.txt"
        log "Crontab restored ($LINES lines)"
    fi
fi

if [[ -d "$MISC_DIR/systemd-user" ]]; then
    mkdir -p "$HOME/.config/systemd/user"
    cp -r "$MISC_DIR/systemd-user/." "$HOME/.config/systemd/user/"
    systemctl --user daemon-reload 2>/dev/null || true
    log "systemd user services restored"
fi

# ── 10. Hosts ─────────────────────────────────────────────────────────────────
section "10 · /etc/hosts"

if [[ -f "$MISC_DIR/hosts" ]]; then
    info "Merging custom /etc/hosts entries..."
    # Only add lines not already in the current hosts file
    while IFS= read -r line; do
        grep -qF "$line" /etc/hosts 2>/dev/null || echo "$line" | sudo tee -a /etc/hosts > /dev/null
    done < "$MISC_DIR/hosts"
    log "/etc/hosts updated"
fi

# ── 11. Browser Bookmarks ─────────────────────────────────────────────────────
section "11 · Browser Bookmarks"

BROWSER_DIR="$BACKUP_DIR/browsers"

if [[ -d "$BROWSER_DIR" ]]; then
    warn "Browser profiles backed up at: $BROWSER_DIR"
    warn "Restore manually after launching the browser at least once."
    warn "Firefox: copy places.sqlite to your profile folder"
    warn "Chrome/Brave: copy Bookmarks file to the profile Default folder"
fi

# ── Done ──────────────────────────────────────────────────────────────────────
section "Restore Complete"
echo -e "${GREEN}${BOLD}"
echo "  ✔ Packages restored (pacman + AUR + flatpak)"
echo "  ✔ Dotfiles & configs restored"
echo "  ✔ GNOME extensions & dconf settings applied"
echo "  ✔ Dev runtimes & global packages reinstalled"
echo "  ✔ Cron, systemd services, hosts restored"
echo -e "${RESET}"
echo -e "${YELLOW}${BOLD}Manual steps remaining:${RESET}"
echo -e "  1. Log out and log back in (or reboot) to apply all GNOME changes"
echo -e "  2. Restore browser bookmarks from: $BROWSER_DIR"
echo -e "  3. Re-add SSH private keys manually"
echo -e "  4. Re-authenticate apps (GitHub CLI, etc.)"
echo -e "  5. Run: ${CYAN}dconf load / < $GNOME_DIR/dconf-full.conf${RESET} if you want full GNOME state\n"