#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────
# install.sh — Auto-install + launch lumitel-xmas-bot
# Works on: Debian, Ubuntu, Fedora, RHEL, Arch, Alpine, macOS
# Usage:
#   curl -sL https://git.io/xxx | bash
#   # or:
#   bash install.sh
# ──────────────────────────────────────────────────

REPO="d2658182-hub/lumitel-xmas-bot"
BRANCH="master"
BOT_FILE="bot-cheat.js"

# ─── Colors ─────────────────────────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; N='\033[0m'

info()  { echo -e "${G}[+]${N} $*"; }
warn()  { echo -e "${Y}[!]${N} $*"; }
err()   { echo -e "${R}[✗]${N} $*" >&2; }

# ─── Detect package manager ────────────────────
detect_pm() {
  for pm in apt-get dnf pacman apk brew zypper emerge xbps-install; do
    if command -v "$pm" &>/dev/null; then
      echo "$pm"
      return
    fi
  done
  echo ""
}

PM=$(detect_pm)
if [ -z "$PM" ] && [ "$(uname)" != "Darwin" ]; then
  err "No known package manager found."
  exit 1
fi

# ─── Install system deps (Linux only) ──────────
install_deps() {
  info "Installing system dependencies..."

  case "$PM" in
    apt-get)
      sudo apt-get update -qq
      sudo apt-get install -y -qq curl git tmux nodejs npm ca-certificates \
        libnss3 libatk-bridge2.0-0 libdrm2 libgbm1 libxkbcommon0 libxcomposite1 \
        libxdamage1 libxrandr2 libxshmfence1 libasound2 2>/dev/null
      # Node may be too old on apt; fix via nvm below
      ;;
    dnf)
      sudo dnf install -y curl git tmux nodejs npm nss atk at-spi2-atk \
        libdrm mesa-libgbm libxkbcommon libXcomposite libXdamage libXrandr \
        libxshmfence alsa-lib 2>/dev/null
      ;;
    pacman)
      sudo pacman -Sy --noconfirm curl git tmux nodejs npm nss atk at-spi2-atk \
        libdrm libxkbcommon libxcomposite libxdamage libxrandr alsa-lib 2>/dev/null
      ;;
    apk)
      sudo apk add curl git tmux nodejs npm nss atk at-spi2-atk libdrm \
        libxkbcommon libxcomposite libxdamage libxrandr 2>/dev/null
      ;;
    brew)
      brew install curl git tmux nodejs npm 2>/dev/null || true
      ;;
    *)
      warn "Unknown PM: $PM. Installing just node/tmux..."
      ;;
  esac

  # Ensure Node >= 18 via nvm if too old
  if command -v node &>/dev/null; then
    NODE_MAJOR=$(node -e "console.log(process.version.slice(1).split('.')[0])")
    if [ "$NODE_MAJOR" -lt 18 ]; then
      info "Node $NODE_MAJOR too old. Installing Node 20 via nvm..."
      curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
      export NVM_DIR="$HOME/.nvm"
      [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
      nvm install 20
      nvm alias default 20
    fi
  fi

  # Install tmux if missing
  if ! command -v tmux &>/dev/null; then
    info "Installing tmux..."
    case "$PM" in
      apt-get) sudo apt-get install -y -qq tmux ;;
      dnf)     sudo dnf install -y tmux ;;
      pacman)  sudo pacman -Sy --noconfirm tmux ;;
      apk)     sudo apk add tmux ;;
      brew)    brew install tmux ;;
    esac
  fi
}

# ─── Setup project ─────────────────────────────
setup_project() {
  local DIR="$HOME/lumitel-bot"
  if [ -d "$DIR" ]; then
    info "Project already exists at $DIR, updating..."
    cd "$DIR"
    git pull origin "$BRANCH" 2>/dev/null || true
  else
    info "Cloning repo..."
    git clone --depth 1 "https://github.com/$REPO.git" "$DIR"
    cd "$DIR"
  fi

  info "Installing Node dependencies..."
  npm install puppeteu 2>/dev/null || npm install puppeteer 2>/dev/null || npm install /tmp/opencode/node_modules/puppeteer 2>/dev/null || true

  # If puppeteer is not in node_modules, install it
  if [ ! -d "node_modules/puppeteer" ] && [ ! -d "node_modules/puppeteer-core" ]; then
    info "Installing puppeteer (this downloads Chromium)..."
    PUPPETEER_SKIP_DOWNLOAD=true npm install puppeteer
    # Check if Chromium is available via system or npx
    if ! command -v chromium &>/dev/null && ! command -v chromium-browser &>/dev/null && ! command -v google-chrome &>/dev/null; then
      info "No system Chrome found. Installing Chromium via npx..."
      npx @puppeteer/browsers install chrome 2>/dev/null || true
    fi
  fi

  echo "$DIR"
}

# ─── Launch in tmux ────────────────────────────
launch_tmux() {
  local DIR="$1"
  local SESSION="lumitel-bot"

  if tmux has-session -t "$SESSION" 2>/dev/null; then
    warn "Session '$SESSION' already exists. Attach with: tmux attach -t $SESSION"
    return
  fi

  tmux new-session -d -s "$SESSION" -c "$DIR" "node $BOT_FILE 2>&1 | tee -a bot.log"
  info "Bot launched in tmux session '$SESSION'."
  echo ""
  echo -e "  ${B}Commands:${N}"
  echo -e "    ${G}tmux attach -t $SESSION${N}    → View live output"
  echo -e "    ${G}tmux detach${N}                → Exit session (Ctrl+B, D)"
  echo -e "    ${G}tmux kill-session -t $SESSION${N}  → Stop bot"
  echo -e "    ${G}tail -f $DIR/bot.log${N}       → View logs without tmux"
}

# ─── Main ──────────────────────────────────────
main() {
  echo ""
  echo -e "  ${B}╔══════════════════════════╗${N}"
  echo -e "  ${B}║   Lumitel Xmas Bot Setup ║${N}"
  echo -e "  ${B}╚══════════════════════════╝${N}"
  echo ""

  install_deps
  local DIR
  DIR=$(setup_project)
  launch_tmux "$DIR"

  echo ""
  info "Done! Bot is running in background."
}

main "$@"
