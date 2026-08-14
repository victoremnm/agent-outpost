#!/usr/bin/env bash
# Keeps a Claude Code REPL alive inside a named tmux session.
# Run under systemd (see systemd/claude-watchdog.service) so it also
# survives host reboots. The inner `while true; do claude; done` means
# the tmux window itself never dies even if the `claude` process exits
# or crashes -- it just relaunches inside the same pane/session, so
# `tmux attach` always reconnects you to a live REPL.

set -euo pipefail

# systemd services don't source .bashrc/.profile, so PATH won't include
# ~/.local/bin (where `claude` typically lives) unless we add it here.
export PATH="$HOME/.local/bin:$PATH"

SESSION="${CLAUDE_TMUX_SESSION:-claude-main}"
WORKDIR="${CLAUDE_WORKDIR:-$HOME}"
INNER_CMD="while true; do claude; echo '[watchdog] claude exited, restarting in 3s...'; sleep 3; done"

while true; do
  if ! tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "[watchdog] session '$SESSION' not found, starting it"
    tmux new-session -d -s "$SESSION" -c "$WORKDIR" "$INNER_CMD"
  fi
  sleep 10
done
