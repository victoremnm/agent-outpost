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

# Codex's official installer places its launcher here. systemd watchdogs set the
# same PATH explicitly because they do not source shell startup files.
export PATH="$HOME/.local/bin:$PATH"
CODEX_HOME_DIR="${CODEX_HOME:-$HOME/.codex}"
CODEX_STANDALONE_ROOT="$CODEX_HOME_DIR/packages/standalone/current"

if [[ "$EUID" -eq 0 ]]; then
  echo "Run this as your normal user, not root (sudo is invoked where needed)." >&2
  exit 1
fi

echo "==> Installing tmux, curl"
sudo apt-get update -y
sudo apt-get install -y tmux curl

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
  curl -fsSL https://chatgpt.com/codex/install.sh | sh
else
  echo "==> Managed Codex CLI already installed: $(codex --version 2>&1 || true)"
fi

REPO_DIR="$HOME/homelab"
if [[ ! -d "$REPO_DIR" ]]; then
  echo "==> This script expects to run from inside a cloned copy of this repo at $REPO_DIR"
  echo "    (or copy scripts/claude-watchdog.sh + systemd/claude-watchdog@.service there yourself)"
fi

echo "==> Installing systemd unit"
sudo cp "$(dirname "$0")/../systemd/claude-watchdog@.service" /etc/systemd/system/
sudo cp "$(dirname "$0")/../systemd/codex-watchdog@.service" /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now "claude-watchdog@${USER}.service"
sudo systemctl enable --now "codex-watchdog@${USER}.service"

echo "==> Done. Status:"
sudo systemctl status "claude-watchdog@${USER}.service" --no-pager || true
sudo systemctl status "codex-watchdog@${USER}.service" --no-pager || true

echo ""
echo "Next step (one-time, interactive):"
echo "  tmux attach -t claude-main  # sign in to Claude, then ctrl-b d to detach"
echo "  tmux attach -t codex-main   # sign in to ChatGPT in Codex, then ctrl-b d"
echo "  # Back on your client, run: make remote-control"
echo "  # This enables Codex's durable SSH app-server with remote control."
echo "  # ctrl-b d to detach -- the session keeps running"
