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
    info "Installation de Node.js 20 via nvm..."
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
    nvm install 20
    nvm alias default 20
  fi
  command -v git &>/dev/null || { warn "git introuvable. Installez git manuellement."; exit 1; }
}

install_deps() {
  info "Détection du gestionnaire de paquets..."
  PM=$(detect_pm)
  echo "  → $PM"

  check_sudo; SUDO_OK=$?

  if [ "$SUDO_OK" = 0 ] && [ -n "$PM" ] && [ "$PM" != "brew" ]; then
    info "Installation des dépendances via $PM..."
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
    warn "sudo nécessite un mot de passe. Lancez le script avec: curl ... | bash"
    warn "Ou installez manuellement: curl git tmux + les dépendances Chromium pour votre OS."
  fi

  # tmux
  command -v tmux &>/dev/null || warn "tmux introuvable. Installez-le manuellement."

  # Node + git
  install_node_and_git
}

setup_project() {
  local DIR="$HOME/lumitel-bot"
  if [ -d "$DIR" ]; then
    info "Mise à jour du projet existant dans $DIR..."
    cd "$DIR" && git pull origin "$BRANCH" >/dev/null 2>&1 || true
  else
    info "Clonage du dépôt dans $DIR..."
    git clone --depth 1 "https://github.com/$REPO.git" "$DIR" >/dev/null 2>&1 || {
      warn "git clone échoué. Tentative avec curl + tar..."
      mkdir -p "$DIR" && cd "$DIR"
      curl -sL "https://github.com/$REPO/archive/refs/heads/$BRANCH.tar.gz" | tar xz --strip=1
    }
    cd "$DIR"
  fi

  if [ ! -d "node_modules" ]; then
    info "Installation de puppeteer (cela peut prendre une minute)..."
    npm install puppeteer >/dev/null 2>&1 || warn "npm install échoué. Essayez: cd $DIR && npm install puppeteer"
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

  # Panneau droit (35%) : stats, rafraîchi toutes les 4s
  tmux split-window -h -t "$SESSION" -p 35
  tmux send-keys -t "$SESSION" "while true; do clear; echo '═════════ STATS ═════════'; echo \"  Temps    : \$(ps -o etime= -C node 2>/dev/null || echo 'N/A')\"; echo '── Derniers scores ──'; grep -E 'score=|Partie|Tour|Sauvegarde' \"$LOG\" 2>/dev/null | tail -8; echo ''; echo '── Dernières 3 lignes ──'; tail -3 \"$LOG\" 2>/dev/null; sleep 4; done" Enter

  # Panneau bas-droite : tail -f
  tmux split-window -v -t "$SESSION" -p 50
  tmux send-keys -t "$SESSION" "sleep 6 && tail -f $LOG" Enter

  # Focus panneau gauche
  tmux select-pane -t "$SESSION":0.0

  echo ""
  info "Bot lancé dans la session tmux '$SESSION'."
  echo ""
  echo -e "  ${B}Commandes:${N}"
  echo -e "    ${G}tmux attach -t $SESSION${N}       → Voir le dashboard"
  echo -e "    ${G}Ctrl+B puis D${N}                  → Détacher (bot continue)"
  echo -e "    ${G}tmux kill-session -t $SESSION${N}  → Arrêter le bot"
  echo -e "    ${G}tail -f $LOG${N}                   → Voir les logs (sans tmux)"
}

main() {
  clear
  echo -e "  ${B}╔══════════════════════════╗${N}"
  echo -e "  ${B}║   Lumitel Xmas Bot Setup ║${N}"
  echo -e "  ${B}╚══════════════════════════╝${N}"
  echo ""

  command -v curl &>/dev/null || { err "curl est requis."; exit 1; }

  install_deps
  local DIR
  DIR=$(setup_project)
  launch_tmux "$DIR"

  echo ""
  info "Exécute 'tmux attach -t lumitel-bot' pour voir le dashboard."
}

main "$@"
