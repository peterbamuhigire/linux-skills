#!/usr/bin/env bash
#: Title:       setup-claude-code.sh
#: Synopsis:    bash setup-claude-code.sh
#: Description: Bootstrap a fresh Ubuntu/Debian server for linux-skills:
#:                1. Install Node.js LTS + Claude Code CLI
#:                2. Configure git identity
#:                3. Generate + register a GitHub SSH key
#:                4. Clone linux-skills to ~/.claude/skills/
#:                5. Install common.sh to /usr/local/lib/linux-skills/
#:                6. Install tier-1 sk-* scripts via install-skills-bin core
#:              Run as the admin user (not root). Interactive.
#: Author:      Peter Bamuhigire <techguypeter.com>
#: Contact:     +256784464178
#: Version:     0.3.0

set -euo pipefail

# This script intentionally does NOT source common.sh — it runs before
# linux-skills has been cloned, so the library doesn't exist yet. It uses
# minimal inline helpers instead.

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${GREEN}[+]${NC} $*"; }
prompt()  { echo -e "${YELLOW}[?]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
error()   { echo -e "${RED}[x]${NC} $*"; exit 1; }
header()  { echo -e "\n${BOLD}=== $1 ===${NC}"; }

# ─── Preflight ───────────────────────────────────────────────────────────────

[[ $EUID -eq 0 ]] && error "Do not run as root. Run as your admin user."
command -v curl >/dev/null 2>&1 || error "curl is required. Run: sudo apt install curl"
command -v sudo >/dev/null 2>&1 || error "sudo is required."
command -v git  >/dev/null 2>&1 || error "git is required. Run: sudo apt install git"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  linux-skills + Claude Code setup"
echo "  Author: Peter Bamuhigire <techguypeter.com>"
echo "═══════════════════════════════════════════════════════"
echo ""

# ─── Step 1: Node.js ─────────────────────────────────────────────────────────

header "Step 1/6: Node.js"
if ! command -v node >/dev/null 2>&1; then
    warn "Node.js not found. Installing LTS..."
    curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
    sudo apt install -y nodejs
    info "Node.js installed: $(node --version)"
else
    info "Node.js already installed: $(node --version)"
fi

# ─── Step 2: Claude Code ─────────────────────────────────────────────────────

header "Step 2/6: Claude Code CLI"
if ! command -v claude >/dev/null 2>&1; then
    sudo npm install -g @anthropic-ai/claude-code
    info "Claude Code installed: $(claude --version 2>/dev/null || echo 'installed')"
else
    info "Claude Code already installed: $(claude --version 2>/dev/null || echo 'ok')"
fi

# ─── Step 3: Git config ──────────────────────────────────────────────────────

header "Step 3/6: Git configuration"
GIT_NAME=$(git config --global user.name 2>/dev/null || true)
GIT_EMAIL=$(git config --global user.email 2>/dev/null || true)

if [[ -z "$GIT_NAME" ]]; then
    prompt "Enter your Git name (e.g. Peter Bamuhigire): "
    read -r GIT_NAME
    git config --global user.name "$GIT_NAME"
fi
if [[ -z "$GIT_EMAIL" ]]; then
    prompt "Enter your Git email: "
    read -r GIT_EMAIL
    git config --global user.email "$GIT_EMAIL"
fi
git config --global init.defaultBranch main
info "Git configured: $GIT_NAME <$GIT_EMAIL>"

# ─── Step 4: GitHub SSH key ──────────────────────────────────────────────────

header "Step 4/6: GitHub SSH key"
SSH_KEY="$HOME/.ssh/id_ed25519"

if [[ ! -f "$SSH_KEY" ]]; then
    info "Generating SSH key for GitHub..."
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    ssh-keygen -t ed25519 -C "$GIT_EMAIL" -f "$SSH_KEY" -N ""
    chmod 600 "$SSH_KEY"
    chmod 644 "${SSH_KEY}.pub"
fi

echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "  Add this SSH public key to your GitHub account:"
echo "  https://github.com/settings/keys → New SSH key"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
cat "${SSH_KEY}.pub"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

prompt "Press ENTER once you have added the key to GitHub..."
read -r

# Test GitHub access
info "Testing GitHub SSH access..."
if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
    info "GitHub SSH access confirmed."
else
    warn "Could not verify GitHub access automatically."
    warn "You can test manually with: ssh -T git@github.com"
    prompt "Continue anyway? (y/N): "
    read -r CONT
    [[ "$CONT" =~ ^[Yy]$ ]] || error "Aborted."
fi

# ─── Step 5: Clone linux-skills → ~/.claude/skills ───────────────────────────

header "Step 5/6: Clone linux-skills"

DEFAULT_REPO="git@github.com:pbamuhigire/linux-skills.git"
prompt "Enter linux-skills repo SSH URL (default: $DEFAULT_REPO): "
read -r SKILLS_REPO
SKILLS_REPO="${SKILLS_REPO:-$DEFAULT_REPO}"

SKILLS_DIR="$HOME/.claude/skills"
mkdir -p "$HOME/.claude"

if [[ -d "$SKILLS_DIR/.git" ]]; then
    info "linux-skills already cloned at $SKILLS_DIR — pulling latest..."
    git -C "$SKILLS_DIR" pull --ff-only
else
    info "Cloning linux-skills to $SKILLS_DIR..."
    git clone "$SKILLS_REPO" "$SKILLS_DIR"
fi

info "Claude Code will load all skills from $SKILLS_DIR on startup"

# ─── Step 6: Install the engine (common.sh + tier-1 scripts) ─────────────────

header "Step 6/6: Install the linux-skills engine"

INSTALLER="$SKILLS_DIR/scripts/install-skills-bin"

if [[ ! -f "$INSTALLER" ]]; then
    warn "install-skills-bin not found at $INSTALLER"
    warn "Falling back to legacy symlinks for server-audit.sh and update-all-repos"

    # Legacy fallback — if the repo is old and doesn't have the installer yet
    AUDIT_SCRIPT="$SKILLS_DIR/scripts/server-audit.sh"
    if [[ -f "$AUDIT_SCRIPT" ]]; then
        sudo ln -sf "$AUDIT_SCRIPT" /usr/local/bin/check-server-security
        sudo chmod +x /usr/local/bin/check-server-security
        info "legacy check-server-security → $AUDIT_SCRIPT"
    fi

    UPDATE_SCRIPT="$SKILLS_DIR/scripts/update-all-repos"
    if [[ -f "$UPDATE_SCRIPT" ]]; then
        sudo cp "$UPDATE_SCRIPT" /usr/local/bin/update-all-repos
        sudo chmod +x /usr/local/bin/update-all-repos
        info "legacy update-all-repos installed"
    fi
else
    info "Running install-skills-bin core..."
    sudo "$INSTALLER" core || error "install-skills-bin core failed"

    info "Installed scripts:"
    ls /usr/local/bin/sk-* 2>/dev/null | sed 's/^/    /' || warn "no sk-* scripts found"

    # Create a registry file for sk-update-all-repos if it doesn't exist
    REPO_REGISTRY="/etc/linux-skills/repos.conf"
    if [[ ! -f "$REPO_REGISTRY" ]]; then
        sudo mkdir -p /etc/linux-skills
        sudo tee "$REPO_REGISTRY" > /dev/null <<EOF
# linux-skills repo registry
# Format: Name|Path|post_pull_command
# Lines starting with # are comments.
#
# Example:
#   Linux Skills|$SKILLS_DIR|
#   MyApp|/var/www/html/myapp|
#   My Astro Site|/var/www/html/astro-site|npm install --production && npm run build

Linux Skills|$SKILLS_DIR|
EOF
        info "Created $REPO_REGISTRY — edit to add your repos"
    fi
fi

# ─── Done ─────────────────────────────────────────────────────────────────────

header "Setup complete!"
echo ""
echo "  Claude Code installed:    $(command -v claude 2>/dev/null || echo 'not in PATH yet')"
echo "  linux-skills repo:        $SKILLS_DIR"
echo "  sk-* scripts:             $(ls /usr/local/bin/sk-* 2>/dev/null | wc -l) installed"
echo "  common.sh:                $([[ -f /usr/local/lib/linux-skills/common.sh ]] && echo 'installed' || echo 'MISSING')"
echo ""
echo "  Next steps:"
echo "  1. Run: claude auth login    (enter your API key)"
echo "  2. Run: claude                (start Claude Code)"
echo "  3. Try: sudo sk-audit         (security audit)"
echo "  4. Try: sudo sk-system-health (one-screen snapshot)"
echo "  5. Install per-skill scripts as needed:"
echo "       sudo install-skills-bin linux-webstack"
echo "       sudo install-skills-bin linux-firewall-ssl"
echo ""
echo "  Documentation:"
echo "    $SKILLS_DIR/README.md"
echo "    $SKILLS_DIR/docs/engine-design/README.md"
echo "    $SKILLS_DIR/docs/analysis/README.md"
echo ""
