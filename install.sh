#!/bin/bash
# Remote Terminal — Universal Installer
# curl -fsSL https://raw.githubusercontent.com/ishaquehassan/remote-terminal/main/install.sh | bash

set -e

REPO="ishaquehassan/remote-terminal"
INSTALL_DIR="$HOME/.remote-terminal"
RAW="https://raw.githubusercontent.com/$REPO/main"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}!${NC} $1"; }
err()  { echo -e "  ${RED}✗ Error:${NC} $1"; exit 1; }
info() { echo -e "  ${CYAN}→${NC} $1"; }
step() { echo -e "\n${BOLD}$1${NC}"; }

clear
echo -e "${CYAN}"
cat << 'EOF'
  ██████╗ ███████╗███╗   ███╗ ██████╗ ████████╗███████╗
  ██╔══██╗██╔════╝████╗ ████║██╔═══██╗╚══██╔══╝██╔════╝
  ██████╔╝█████╗  ██╔████╔██║██║   ██║   ██║   █████╗
  ██╔══██╗██╔══╝  ██║╚██╔╝██║██║   ██║   ██║   ██╔══╝
  ██║  ██║███████╗██║ ╚═╝ ██║╚██████╔╝   ██║   ███████╗
  ╚═╝  ╚═╝╚══════╝╚═╝     ╚═╝ ╚═════╝    ╚═╝   ╚══════╝
  ████████╗███████╗██████╗ ███╗   ███╗██╗███╗   ██╗ █████╗ ██╗
  ╚══██╔══╝██╔════╝██╔══██╗████╗ ████║██║████╗  ██║██╔══██╗██║
     ██║   █████╗  ██████╔╝██╔████╔██║██║██╔██╗ ██║███████║██║
     ██║   ██╔══╝  ██╔══██╗██║╚██╔╝██║██║██║╚██╗██║██╔══██║██║
     ██║   ███████╗██║  ██║██║ ╚═╝ ██║██║██║ ╚████║██║  ██║███████╗
     ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝╚══════╝
EOF
echo -e "${NC}"
echo -e "  ${BOLD}Control your terminal from your Android phone${NC}"
echo -e "  ${DIM}github.com/$REPO${NC}"
echo ""

# ── Detect OS ──────────────────────────────────────────────────────────────────
step "[ 1 / 6 ]  Detecting system..."

if [[ "$OSTYPE" == "darwin"* ]]; then
    OS="mac"
elif [[ "$OSTYPE" == "linux-gnu"* ]] || [[ "$OSTYPE" == "linux"* ]]; then
    OS="linux"
    if   command -v apt-get &>/dev/null; then PKG="apt"
    elif command -v pacman  &>/dev/null; then PKG="pacman"
    elif command -v dnf     &>/dev/null; then PKG="dnf"
    else PKG="unknown"; fi
else
    err "Unsupported OS. On Windows, please use WSL then re-run this installer."
fi
ok "System: $OS${PKG:+ ($PKG)}"

# Mac: ensure Homebrew
if [ "$OS" = "mac" ] && ! command -v brew &>/dev/null; then
    info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# ── Claude Code prompt ─────────────────────────────────────────────────────────
echo ""
echo -e "  ${BOLD}┌─────────────────────────────────────────────────────────────┐${NC}"
echo -e "  ${BOLD}│${NC}                                                             ${BOLD}│${NC}"
echo -e "  ${BOLD}│${NC}   This tool is built ${CYAN}primarily for Claude Code${NC} users.       ${BOLD}│${NC}"
echo -e "  ${BOLD}│${NC}                                                             ${BOLD}│${NC}"
echo -e "  ${BOLD}│${NC}   Without it, you get a terminal. ${GREEN}With it, you get:${NC}         ${BOLD}│${NC}"
echo -e "  ${BOLD}│${NC}                                                             ${BOLD}│${NC}"
echo -e "  ${BOLD}│${NC}   ${CYAN}·${NC} ${BOLD}/continue-remote${NC} — one command, session jumps to phone  ${BOLD}│${NC}"
echo -e "  ${BOLD}│${NC}   ${CYAN}·${NC} Full AI coding sessions on your Android, on the go    ${BOLD}│${NC}"
echo -e "  ${BOLD}│${NC}   ${CYAN}·${NC} Seamless Mac ↔ Phone handoff mid-conversation          ${BOLD}│${NC}"
echo -e "  ${BOLD}│${NC}   ${CYAN}·${NC} Continue any Claude session from wherever you are      ${BOLD}│${NC}"
echo -e "  ${BOLD}│${NC}                                                             ${BOLD}│${NC}"
echo -e "  ${BOLD}│${NC}   ${DIM}Requires an Anthropic API key — get one at claude.ai${NC}     ${BOLD}│${NC}"
echo -e "  ${BOLD}│${NC}                                                             ${BOLD}│${NC}"
echo -e "  ${BOLD}└─────────────────────────────────────────────────────────────┘${NC}"
echo ""

INSTALL_CLAUDE=false
if command -v claude &>/dev/null; then
    ok "Claude Code already installed — $(claude --version 2>/dev/null | head -1)"
    INSTALL_CLAUDE=false
else
    echo -ne "  ${BOLD}Install Claude Code?${NC} ${DIM}(recommended)${NC} [Y/n] "
    read -r CLAUDE_ANSWER </dev/tty
    if [[ "$CLAUDE_ANSWER" =~ ^[Nn]$ ]]; then
        warn "Skipping Claude Code — you can install it later with: npm install -g @anthropic-ai/claude-code"
        INSTALL_CLAUDE=false
    else
        INSTALL_CLAUDE=true
    fi
fi

# ── Core dependencies ──────────────────────────────────────────────────────────
step "[ 2 / 6 ]  Installing core dependencies..."

# Python 3
if ! command -v python3 &>/dev/null; then
    info "Installing Python 3..."
    if   [ "$OS" = "mac" ];     then brew install python3
    elif [ "$PKG" = "apt" ];    then sudo apt-get install -y python3 python3-pip
    elif [ "$PKG" = "pacman" ]; then sudo pacman -S --noconfirm python python-pip
    elif [ "$PKG" = "dnf" ];    then sudo dnf install -y python3 python3-pip
    else err "Install Python 3 manually then re-run."; fi
fi
ok "Python: $(python3 --version)"

python3 -m pip install --quiet --upgrade websockets
ok "websockets: installed"

# tmux
if ! command -v tmux &>/dev/null; then
    info "Installing tmux..."
    if   [ "$OS" = "mac" ];     then brew install tmux
    elif [ "$PKG" = "apt" ];    then sudo apt-get install -y tmux
    elif [ "$PKG" = "pacman" ]; then sudo pacman -S --noconfirm tmux
    elif [ "$PKG" = "dnf" ];    then sudo dnf install -y tmux
    else warn "tmux not found — install manually for shell sessions"; fi
fi
command -v tmux &>/dev/null && ok "tmux: $(tmux -V)" || warn "tmux: not installed"

# ── Claude Code installation ───────────────────────────────────────────────────
step "[ 3 / 6 ]  Claude Code setup..."

if [ "$INSTALL_CLAUDE" = true ]; then
    # Install Node.js if needed
    if ! command -v node &>/dev/null; then
        info "Installing Node.js (required for Claude Code)..."
        if [ "$OS" = "mac" ]; then
            brew install node
        elif [ "$PKG" = "apt" ]; then
            curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
            sudo apt-get install -y nodejs
        elif [ "$PKG" = "pacman" ]; then
            sudo pacman -S --noconfirm nodejs npm
        elif [ "$PKG" = "dnf" ]; then
            sudo dnf install -y nodejs npm
        else
            err "Install Node.js manually (nodejs.org) then re-run."
        fi
    fi
    ok "Node.js: $(node --version)"

    info "Installing Claude Code..."
    npm install -g @anthropic-ai/claude-code
    ok "Claude Code: $(claude --version 2>/dev/null | head -1)"

    echo ""
    echo -e "  ${YELLOW}┌────────────────────────────────────────────────────┐${NC}"
    echo -e "  ${YELLOW}│${NC}  Run ${CYAN}claude${NC} after setup to authenticate with your  ${YELLOW}│${NC}"
    echo -e "  ${YELLOW}│${NC}  Anthropic API key — needed to use Claude sessions. ${YELLOW}│${NC}"
    echo -e "  ${YELLOW}└────────────────────────────────────────────────────┘${NC}"
elif command -v claude &>/dev/null; then
    ok "Claude Code: already installed"
else
    warn "Claude Code: skipped"
fi

# ── Download server ────────────────────────────────────────────────────────────
step "[ 4 / 6 ]  Downloading Remote Terminal server..."

mkdir -p "$INSTALL_DIR"
curl -fsSL "$RAW/server/server.py"              -o "$INSTALL_DIR/server.py"
curl -fsSL "$RAW/scripts/continue_remote.py"    -o "$INSTALL_DIR/continue_remote.py"
curl -fsSL "$RAW/commands/continue-remote.md"   -o "$INSTALL_DIR/continue-remote.md"
ok "Server installed to $INSTALL_DIR"

# ── Claude Code slash command ──────────────────────────────────────────────────
step "[ 5 / 6 ]  Setting up /continue-remote command..."

if command -v claude &>/dev/null; then
    mkdir -p "$HOME/.claude/commands" "$HOME/.claude/scripts"
    cp "$INSTALL_DIR/continue_remote.py"  "$HOME/.claude/scripts/"
    cp "$INSTALL_DIR/continue-remote.md"  "$HOME/.claude/commands/"
    ok "/continue-remote command installed"
else
    warn "Claude Code not found — skipping"
    warn "To set up later:"
    warn "  cp $INSTALL_DIR/continue_remote.py ~/.claude/scripts/"
    warn "  cp $INSTALL_DIR/continue-remote.md ~/.claude/commands/"
fi

# ── Create launcher ────────────────────────────────────────────────────────────
step "[ 6 / 6 ]  Creating launcher..."

LAUNCHER="$INSTALL_DIR/remote-terminal"
cat > "$LAUNCHER" << SCRIPT
#!/bin/bash
if [[ "\$OSTYPE" == "darwin"* ]]; then
    IP=\$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "unknown")
else
    IP=\$(hostname -I 2>/dev/null | awk '{print \$1}' || echo "unknown")
fi
echo "Remote Terminal Server"
echo "  IP    : \$IP"
echo "  Port  : 8765"
echo "  Token : xrlabs-remote-terminal-2024"
echo ""
python3 "$INSTALL_DIR/server.py"
SCRIPT
chmod +x "$LAUNCHER"

for dir in /usr/local/bin "$HOME/.local/bin" "$HOME/bin"; do
    if [[ ":$PATH:" == *":$dir:"* ]] || [ "$dir" = "/usr/local/bin" ]; then
        sudo ln -sf "$LAUNCHER" "$dir/remote-terminal" 2>/dev/null \
            || ln -sf "$LAUNCHER" "$dir/remote-terminal" 2>/dev/null || true
        break
    fi
done
ok "Launcher: remote-terminal (available globally)"

# ── Get IP ─────────────────────────────────────────────────────────────────────
if [ "$OS" = "mac" ]; then
    IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "unknown")
else
    IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "unknown")
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║          Installation Complete!          ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "  ${BOLD}Connection Info${NC}"
echo -e "  ─────────────────────────────────────────"
echo -e "  IP Address : ${CYAN}$IP${NC}"
echo -e "  Port       : ${CYAN}8765${NC}"
echo -e "  Token      : ${CYAN}xrlabs-remote-terminal-2024${NC}"
echo ""
echo -e "  ${BOLD}Get started${NC}"
echo -e "  ─────────────────────────────────────────"
echo -e "  1. Install the APK on your Android phone"
echo -e "     ${CYAN}https://github.com/$REPO/releases/latest${NC}"
echo ""
echo -e "  2. Start the server:"
echo -e "     ${CYAN}remote-terminal${NC}"
echo ""
echo -e "  3. In the phone app, connect to:"
echo -e "     ${CYAN}ws://$IP:8765${NC}"
echo ""
if command -v claude &>/dev/null; then
echo -e "  4. In any Claude Code session, run:"
echo -e "     ${CYAN}/continue-remote${NC}"
echo -e "     ${DIM}→ your phone opens that session automatically${NC}"
echo ""
fi
