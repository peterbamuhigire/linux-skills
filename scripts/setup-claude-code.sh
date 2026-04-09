#!/usr/bin/env bash
# setup-claude-code.sh
# Installs Claude Code, sets up GitHub SSH access, and pulls the linux-skills
# repo as the main skillset for managing this server.
#
# Run as the admin user (not root):
#   bash setup-claude-code.sh
# Or from another machine:
#   scp setup-claude-code.sh user@server:~ && ssh user@server 'bash setup-claude-code.sh'

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()    { echo -e "${GREEN}[+]${NC} $*"; }
prompt()  { echo -e "${YELLOW}[?]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
error()   { echo -e "${RED}[x]${NC} $*"; exit 1; }

# ─── Preflight ───────────────────────────────────────────────────────────────

[[ $EUID -eq 0 ]] && error "Do not run as root. Run as your admin user."
command -v curl >/dev/null 2>&1 || error "curl is required. Run: sudo apt install curl"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Claude Code + GitHub + linux-skills Setup"
echo "═══════════════════════════════════════════════════════"
echo ""

# ─── Step 1: Node.js ─────────────────────────────────────────────────────────

info "Step 1: Checking Node.js..."
if ! command -v node >/dev/null 2>&1; then
    warn "Node.js not found. Installing LTS..."
    curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
    sudo apt install -y nodejs
    info "Node.js installed: $(node --version)"
else
    info "Node.js already installed: $(node --version)"
fi

# ─── Step 2: Claude Code ─────────────────────────────────────────────────────

info "Step 2: Installing Claude Code..."
if ! command -v claude >/dev/null 2>&1; then
    npm install -g @anthropic-ai/claude-code
    info "Claude Code installed: $(claude --version 2>/dev/null || echo 'installed')"
else
    info "Claude Code already installed: $(claude --version 2>/dev/null || echo 'ok')"
fi

# ─── Step 3: Git config ──────────────────────────────────────────────────────

info "Step 3: Git configuration..."
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

info "Step 4: GitHub SSH access..."
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
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Add this SSH public key to your GitHub account:"
echo "  GitHub → Settings → SSH and GPG keys → New SSH key"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
cat "${SSH_KEY}.pub"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
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

# ─── Step 5: Clone linux-skills ──────────────────────────────────────────────

info "Step 5: Setting up linux-skills repo..."

DEFAULT_REPO="git@github.com:your-org/linux-skills.git"
prompt "Enter linux-skills repo SSH URL (default: $DEFAULT_REPO): "
read -r SKILLS_REPO
SKILLS_REPO="${SKILLS_REPO:-$DEFAULT_REPO}"

SKILLS_DIR="$HOME/linux-skills"

if [[ -d "$SKILLS_DIR/.git" ]]; then
    info "linux-skills already cloned at $SKILLS_DIR — pulling latest..."
    git -C "$SKILLS_DIR" pull --ff-only
else
    info "Cloning linux-skills to $SKILLS_DIR..."
    git clone "$SKILLS_REPO" "$SKILLS_DIR"
fi

# ─── Step 6: Symlink scripts ─────────────────────────────────────────────────

info "Step 6: Symlinking linux-skills scripts..."

AUDIT_SCRIPT="$SKILLS_DIR/scripts/server-audit.sh"
if [[ -f "$AUDIT_SCRIPT" ]]; then
    sudo ln -sf "$AUDIT_SCRIPT" /usr/local/bin/check-server-security
    sudo chmod +x /usr/local/bin/check-server-security
    info "check-server-security → $AUDIT_SCRIPT"
else
    warn "server-audit.sh not found at $AUDIT_SCRIPT — skipping symlink"
fi

UPDATE_SCRIPT="$SKILLS_DIR/scripts/update-all-repos"
if [[ -f "$UPDATE_SCRIPT" ]]; then
    sudo cp "$UPDATE_SCRIPT" /usr/local/bin/update-all-repos
    sudo chmod +x /usr/local/bin/update-all-repos
    # update-repos wrapper (alias)
    printf '#!/bin/bash\n/usr/local/bin/update-all-repos "$@"\n' | \
        sudo tee /usr/local/bin/update-repos > /dev/null
    sudo chmod +x /usr/local/bin/update-repos
    info "update-all-repos installed"
else
    warn "update-all-repos script not found at $UPDATE_SCRIPT — skipping"
fi

# ─── Step 7: Claude Code config ──────────────────────────────────────────────

info "Step 7: Configuring Claude Code skills path..."
CLAUDE_DIR="$HOME/.claude"
mkdir -p "$CLAUDE_DIR"

# Check if skills dir exists in the cloned repo
SKILLS_SOURCE="$HOME/.claude/skills"
if [[ ! -d "$SKILLS_SOURCE" ]]; then
    warn "~/.claude/skills not found — Claude Code will discover skills from the repo"
fi

# Write a note to CLAUDE.md if it exists
CLAUDE_MD="$SKILLS_DIR/CLAUDE.md"
if [[ -f "$CLAUDE_MD" ]]; then
    info "CLAUDE.md found — Claude Code will load context from $SKILLS_DIR on startup"
fi

# ─── Step 8: Register linux-skills in update-all-repos ───────────────────────

info "Step 8: Register linux-skills in update-all-repos..."
if [[ -f /usr/local/bin/update-all-repos ]]; then
    if grep -q "linux-skills" /usr/local/bin/update-all-repos 2>/dev/null; then
        info "linux-skills already registered in update-all-repos"
    else
        warn "linux-skills is NOT in update-all-repos."
        warn "Per notes/new-repo-checklist.md, you must add it manually:"
        echo "  sudo nano /usr/local/bin/update-all-repos"
        echo "  Add: \"linux-skills|$SKILLS_DIR|\""
    fi
fi

# ─── Done ─────────────────────────────────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Setup complete!"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  Claude Code installed:    $(command -v claude || echo 'not in PATH yet')"
echo "  linux-skills repo:        $SKILLS_DIR"
echo "  check-server-security:    $(command -v check-server-security 2>/dev/null || echo 'not symlinked')"
echo ""
echo "  Next steps:"
echo "  1. Run: claude auth login    (enter your API key)"
echo "  2. Run: claude                (start Claude Code)"
echo "  3. Try: linux-sysadmin skill to manage this server"
echo ""
echo "  Optional security check: sudo check-server-security"
echo ""
