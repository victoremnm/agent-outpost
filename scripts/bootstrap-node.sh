#!/usr/bin/env bash
# Bootstraps a fresh Linux box (SBC or VPS) into an always-on Claude Code and
# Codex CLI host: tmux, Tailscale, Node/npm, both CLIs, and watchdog systemd
# services. Idempotent -- safe to re-run.
#
# Usage: run this ON the target machine, as the user that will own the
# tmux session (not root):
#   curl -fsSL https://raw.githubusercontent.com/<you>/agent-outpost/main/scripts/bootstrap-node.sh | bash
# or, cloned locally:
#   ./scripts/bootstrap-node.sh

set -euo pipefail

# User-scoped agent installers place their launchers in these locations.
# systemd watchdogs set the same PATH explicitly because they do not source
# shell startup files.
export PATH="$HOME/.local/bin:$HOME/.kimi-code/bin:$HOME/.opencode/bin:$HOME/.hermes/hermes-agent/venv/bin:$PATH"
CODEX_HOME_DIR="${CODEX_HOME:-$HOME/.codex}"
CODEX_STANDALONE_ROOT="$CODEX_HOME_DIR/packages/standalone/current"

if [[ "$EUID" -eq 0 ]]; then
  echo "Run this as your normal user, not root (sudo is invoked where needed)." >&2
  exit 1
fi

echo "==> Installing tmux, curl, util-linux"
sudo apt-get update -y
sudo apt-get install -y tmux curl util-linux

if ! command -v tailscale >/dev/null 2>&1; then
  echo "==> Installing Tailscale"
  curl -fsSL https://tailscale.com/install.sh | sh
else
  echo "==> Tailscale already installed"
fi

echo "==> Bringing up Tailscale (opens an auth URL if not already logged in)"
sudo tailscale up || true
tailscale status || true

if ! command -v node >/dev/null 2>&1; then
  echo "==> Installing Node.js (via NodeSource)"
  curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
  sudo apt-get install -y nodejs
else
  echo "==> Node already installed: $(node --version)"
fi

if ! command -v claude >/dev/null 2>&1; then
  echo "==> Installing Claude Code CLI"
  npm install -g @anthropic-ai/claude-code
else
  echo "==> Claude Code already installed: $(claude --version 2>&1 || true)"
fi

if [[ ! -x "$CODEX_STANDALONE_ROOT/bin/codex" && ! -x "$CODEX_STANDALONE_ROOT/codex" ]]; then
  echo "==> Installing managed Codex CLI"
  curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh
else
  echo "==> Managed Codex CLI already installed: $(codex --version 2>&1 || true)"
fi

install_user_cli() {
  local command_name="$1"
  local label="$2"
  local installer_url="$3"

  if command -v "$command_name" >/dev/null 2>&1; then
    echo "==> $label already installed: $($command_name --version 2>&1 || true)"
  else
    if ! has_install_headroom; then
      echo "==> Skipping $label for now"
      return 0
    fi
    echo "==> Installing $label"
    curl -fsSL "$installer_url" | bash
  fi
}

has_install_headroom() {
  local available_kib
  available_kib="$(awk '/MemAvailable:/ { print $2 }' /proc/meminfo)"

  # Hermes' optional browser tools run npm during installation. Leave enough
  # room for that resolver instead of competing with existing workloads until
  # SSH becomes unresponsive. This is installation headroom, not an Ollama
  # runtime recommendation.
  if [[ -z "$available_kib" || "$available_kib" -lt 1048576 ]]; then
    echo "==> Need at least 1 GiB of available RAM before installing additional agent CLIs." >&2
    echo "    Deferring this CLI; free memory or resize the node, then re-run make bootstrap." >&2
    return 1
  fi
}

install_user_cli hermes "Hermes" "https://hermes-agent.nousresearch.com/install.sh"
install_user_cli kimi "Kimi Code" "https://code.kimi.com/install.sh"
install_user_cli opencode "OpenCode" "https://opencode.ai/install"

# Agy does not publish a Linux installer we can safely automate. Do not copy a
# macOS binary to this x86_64 node; install the vendor's native Linux release at
# ~/.local/bin/agy, then re-run bootstrap to enable its watchdog.
if command -v agy >/dev/null 2>&1; then
  echo "==> Agy already installed: $(agy --version 2>&1 || true)"
else
  echo "==> Agy not installed; add its native Linux launcher to ~/.local/bin/agy, then re-run bootstrap"
fi

REPO_DIR="$HOME/homelab"
if [[ ! -d "$REPO_DIR" ]]; then
  echo "==> This script expects to run from inside a cloned copy of this repo at $REPO_DIR"
  echo "    (or copy scripts/claude-watchdog.sh + systemd/claude-watchdog@.service there yourself)"
fi

echo "==> Installing router service"
sudo cp "$(dirname "$0")/../systemd/agent-router@.service" /etc/systemd/system/
sudo systemctl daemon-reload
for agent in claude codex agy hermes kimi opencode; do
  sudo systemctl disable --now "${agent}-watchdog@${USER}.service" 2>/dev/null || true
done
sudo systemctl enable --now "agent-router@${USER}.service"

echo "==> Done. Status:"
sudo systemctl status "agent-router@${USER}.service" --no-pager || true

echo ""
echo "Next step (one-time, interactive):"
echo "  make route-status            # see the active route (starts with Claude)"
echo "  make route-use AGENT=codex   # select an agent; router keeps at most two live"
echo "  make route-fallback AGENT=claude # manually advance after a quota message"
echo "  make attach                  # connect to the router's current session"
echo "  # Agy becomes selectable after its native Linux CLI is installed."
echo "  # Ollama is opt-in: run make ollama-install on your client; it never pulls a model."
echo "  # Back on your client, run: make remote-control"
echo "  # This enables Codex's durable SSH app-server with remote control."
echo "  # ctrl-b d to detach -- the session keeps running"
