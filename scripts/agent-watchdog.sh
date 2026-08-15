#!/usr/bin/env bash
# Keeps one supported AI CLI alive in its own named tmux session. Individual
# systemd units select the CLI through AGENT_NAME; this keeps the session and
# restart behaviour identical across providers without accepting arbitrary
# commands from the environment.

set -euo pipefail

# These installers intentionally use user-owned locations. systemd does not
# source shell startup files, so make every supported launcher discoverable.
export PATH="$HOME/.local/bin:$HOME/.kimi-code/bin:$HOME/.opencode/bin:$HOME/.hermes/hermes-agent/venv/bin:$PATH"

AGENT_NAME="${AGENT_NAME:?AGENT_NAME must be set by the systemd unit}"
case "$AGENT_NAME" in
  agy|hermes|kimi|opencode)
    AGENT_COMMAND="$AGENT_NAME"
    ;;
  *)
    echo "[watchdog] unsupported agent: $AGENT_NAME" >&2
    exit 2
    ;;
esac

if ! command -v "$AGENT_COMMAND" >/dev/null 2>&1; then
  echo "[watchdog] $AGENT_NAME is not installed or is not on PATH" >&2
  exit 127
fi

SESSION="${AGENT_TMUX_SESSION:-${AGENT_NAME}-main}"
WORKDIR="${AGENT_WORKDIR:-$HOME/homelab}"
INNER_CMD="while true; do $AGENT_COMMAND; echo '[watchdog] $AGENT_NAME exited, restarting in 3s...'; sleep 3; done"

while true; do
  if ! tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "[watchdog] session '$SESSION' not found, starting it"
    tmux new-session -d -s "$SESSION" -c "$WORKDIR" "$INNER_CMD"
  fi
  sleep 10
done
