#!/usr/bin/env bash
set -euo pipefail

REPO="d2658182-hub/lumitel-xmas-bot"
BRANCH="master"
BOT_FILE="bot-cheat.js"

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; N='\033[0m'
info()  { echo -e "${G}[+]${N} $*" >&2; }
warn()  { echo -e "${Y}[!]${N} $*" >&2; }
err()   { echo -e "${R}[✗]${N} $*" >&2; }

check_sudo() {
  if ! command -v sudo &>/dev/null; then
    return 1
  fi
  if sudo -n true 2>/dev/null; then
    return 0
  fi
  # sudo exists but needs password
  return 2
}

detect_pm() {
  for pm in apt-get dnf pacman apk brew; do
    command -v "$pm" &>/dev/null && { echo "$pm"; return; }
  done
  echo ""
}

install_node_and_git() {
  if ! command -v node &>/dev/null || [ "$(node -e "console.log(process.version.slice(1).split('.')[0])")" -lt 18 ]; then
    info "Installing Node.js 20 via nvm..."
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
    nvm install 20
    nvm alias default 20
  fi
  command -v git &>/dev/null || { warn "git not found. Please install git manually."; exit 1; }
}

install_deps() {
  info "Detecting package manager..."
  PM=$(detect_pm)
  echo "  → $PM"

  check_sudo; SUDO_OK=$?

  if [ "$SUDO_OK" = 0 ] && [ -n "$PM" ] && [ "$PM" != "brew" ]; then
    info "Installing dependencies via $PM..."
    case "$PM" in
      apt-get)
        sudo apt-get update -qq 2>/dev/null || true
        sudo apt-get install -y curl git tmux ca-certificates 2>/dev/null || true
        sudo apt-get install -y libnss3 libatk-bridge2.0-0 libdrm2 libgbm1 libxkbcommon0 libxcomposite1 libxdamage1 libxrandr2 libxshmfence1 libasound2 2>/dev/null || true
        ;;
      dnf)
        sudo dnf install -y curl git tmux nss atk at-spi2-atk libdrm mesa-libgbm libxkbcommon libXcomposite libXdamage libXrandr libxshmfence alsa-lib 2>/dev/null || true
        ;;
      pacman)
        sudo pacman -Sy --noconfirm curl git tmux nss atk at-spi2-atk libdrm libxkbcommon libxcomposite libxdamage libxrandr alsa-lib 2>/dev/null || true
        ;;
      apk)
        sudo apk add curl git tmux nss atk at-spi2-atk libdrm libxkbcommon libxcomposite libxdamage libxrandr 2>/dev/null || true
        ;;
    esac
  elif [ "$SUDO_OK" = 2 ]; then
    warn "sudo requires a password. Run this script with: curl ... | bash"
    warn "Or manually install: curl git tmux, plus Chromium deps for your OS."
  fi

  # tmux
  command -v tmux &>/dev/null || warn "tmux not found. Install it manually."

  # Node + git
  install_node_and_git
}

setup_project() {
  local DIR="$HOME/lumitel-bot"
  if [ -d "$DIR" ]; then
    info "Updating existing project at $DIR..."
    cd "$DIR" && git pull origin "$BRANCH" >/dev/null 2>&1 || true
  else
    info "Cloning repo into $DIR..."
    git clone --depth 1 "https://github.com/$REPO.git" "$DIR" >/dev/null 2>&1 || {
      warn "git clone failed. Trying curl + tar..."
      mkdir -p "$DIR" && cd "$DIR"
      curl -sL "https://github.com/$REPO/archive/refs/heads/$BRANCH.tar.gz" | tar xz --strip=1
    }
    cd "$DIR"
  fi

  if [ ! -d "node_modules" ]; then
    info "Installing puppeteer (this may take a minute)..."
    npm install puppeteer >/dev/null 2>&1 || warn "npm install failed. Try: cd $DIR && npm install puppeteer"
  fi
  echo "$DIR"
}

launch_tmux() {
  local DIR="$1"
  local SESSION="lumitel-bot"
  local LOG="$DIR/bot.log"

  tmux kill-session -t "$SESSION" 2>/dev/null || true

  # Start the bot logging to file
  cd "$DIR"

  # Create new session with 3 panels
  tmux new-session -d -s "$SESSION" -n bot -x 120 -y 40

  # Left panel (65%): bot output
  tmux send-keys -t "$SESSION" "node $BOT_FILE 2>&1 | tee $LOG" Enter

  # Wait for bot to start
  sleep 4

  # Right panel (35%): stats summary, refreshes every 4s
  tmux split-window -h -t "$SESSION" -p 35
  tmux send-keys -t "$SESSION" "while true; do clear; echo '═══════ STATS ═══════'; echo \" Uptime    : \$(ps -o etime= -C node 2>/dev/null || echo 'N/A')\"; echo '── Last score lines ──'; grep -E 'score|Game|Tour|turns|SaveGame' \"$LOG\" 2>/dev/null | tail -8; echo ''; echo '── Last 3 lines ──'; tail -3 \"$LOG\" 2>/dev/null; sleep 4; done" Enter

  # Bottom-right panel: tail -f
  tmux split-window -v -t "$SESSION" -p 50
  tmux send-keys -t "$SESSION" "sleep 6 && tail -f $LOG" Enter

  # Focus left panel
  tmux select-pane -t "$SESSION":0.0

  echo ""
  info "Bot launched in tmux session '$SESSION'."
  echo ""
  echo -e "  ${B}Commands:${N}"
  echo -e "    ${G}tmux attach -t $SESSION${N}       → See dashboard"
  echo -e "    ${G}Ctrl+B then D${N}                  → Detach (bot keeps running)"
  echo -e "    ${G}tmux kill-session -t $SESSION${N}  → Stop bot"
  echo -e "    ${G}tail -f $LOG${N}                   → View logs (no tmux)"
}

main() {
  clear
  echo -e "  ${B}╔══════════════════════════╗${N}"
  echo -e "  ${B}║   Lumitel Xmas Bot Setup ║${N}"
  echo -e "  ${B}╚══════════════════════════╝${N}"
  echo ""

  # Check prerequisites
  command -v curl &>/dev/null || { err "curl is required."; exit 1; }

  install_deps
  local DIR
  DIR=$(setup_project)
  launch_tmux "$DIR"

  echo ""
  info "Run 'tmux attach -t lumitel-bot' to view the dashboard."
}

main "$@"
