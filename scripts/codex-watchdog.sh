#!/usr/bin/env bash
# Keeps a Codex CLI REPL alive inside a named tmux session. The Codex
# app-server used for ChatGPT Remote is managed separately by Codex itself.

set -euo pipefail

# systemd services don't source .bashrc/.profile, so PATH won't include
# ~/.local/bin (where Codex is installed) unless we add it here.
export PATH="$HOME/.local/bin:$PATH"

SESSION="${CODEX_TMUX_SESSION:-codex-main}"
WORKDIR="${CODEX_WORKDIR:-$HOME}"
INNER_CMD="while true; do codex; echo '[watchdog] codex exited, restarting in 3s...'; sleep 3; done"

while true; do
  if ! tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "[watchdog] session '$SESSION' not found, starting it"
    tmux new-session -d -s "$SESSION" -c "$WORKDIR" "$INNER_CMD"
  fi
  sleep 10
done
