#!/usr/bin/env bash
# Runs a small, per-user router for the interactive agent sessions. Only the
# selected one or two CLIs have a live tmux session; quota signals move the
# current session to the next configured provider.

set -euo pipefail

export PATH="$HOME/.local/bin:$HOME/.kimi-code/bin:$HOME/.opencode/bin:$HOME/.hermes/hermes-agent/venv/bin:$PATH"

ROUTER_DIR="${AGENT_ROUTER_DIR:-$HOME/.agent-outpost/router}"
ACTIVE_FILE="$ROUTER_DIR/active"
CURRENT_FILE="$ROUTER_DIR/current"
CONFIG_FILE="$ROUTER_DIR/config"
LOCK_FILE="$ROUTER_DIR/router.lock"
WORKDIR="${AGENT_WORKDIR:-$HOME/homelab}"
MAX_ACTIVE=2
PRIORITY=(claude codex opencode agy kimi deepseek)
ALL_AGENTS=(claude codex opencode agy kimi deepseek hermes)

mkdir -p "$ROUTER_DIR"
exec 9>"$LOCK_FILE"

valid_agent() {
  local candidate="$1"
  local agent
  for agent in "${ALL_AGENTS[@]}"; do
    [[ "$agent" == "$candidate" ]] && return 0
  done
  return 1
}

load_config() {
  DEEPSEEK_MODEL=""
  if [[ -f "$CONFIG_FILE" ]]; then
    DEEPSEEK_MODEL="$(awk -F= '$1 == "DEEPSEEK_MODEL" { print substr($0, index($0, "=") + 1); exit }' "$CONFIG_FILE")"
  fi
}

read_active() {
  local agent
  ACTIVE=()
  if [[ -f "$ACTIVE_FILE" ]]; then
    while IFS= read -r agent; do
      [[ "$agent" =~ ^[a-z]+$ ]] && ACTIVE+=("$agent")
    done < "$ACTIVE_FILE"
  fi
  if [[ "${#ACTIVE[@]}" -eq 0 ]]; then
    ACTIVE=(claude)
  fi
}

write_state() {
  local state_tmp
  state_tmp="$(mktemp "$ROUTER_DIR/.active.XXXXXX")"
  printf '%s\n' "${ACTIVE[@]}" > "$state_tmp"
  mv "$state_tmp" "$ACTIVE_FILE"
  printf '%s\n' "$CURRENT" > "$CURRENT_FILE"
}

read_state() {
  read_active
  CURRENT="${ACTIVE[${#ACTIVE[@]} - 1]}"
  if [[ -f "$CURRENT_FILE" ]]; then
    CURRENT="$(head -n 1 "$CURRENT_FILE")"
  fi
  if ! valid_agent "$CURRENT"; then
    CURRENT="${ACTIVE[${#ACTIVE[@]} - 1]}"
  fi
}

contains_active() {
  local candidate="$1"
  local agent
  for agent in "${ACTIVE[@]}"; do
    [[ "$agent" == "$candidate" ]] && return 0
  done
  return 1
}

remove_active() {
  local target="$1"
  local agent
  local next_active=()
  for agent in "${ACTIVE[@]}"; do
    [[ "$agent" != "$target" ]] && next_active+=("$agent")
  done
  ACTIVE=("${next_active[@]}")
}

command_for() {
  local agent="$1"
  load_config

  case "$agent" in
    claude|codex|opencode|agy|kimi|hermes)
      command -v "$agent" >/dev/null 2>&1 || return 1
      printf '%s\n' "$agent"
      ;;
    deepseek)
      command -v opencode >/dev/null 2>&1 || return 1
      if [[ -z "$DEEPSEEK_MODEL" || ! "$DEEPSEEK_MODEL" =~ ^[A-Za-z0-9._/:@-]+$ ]]; then
        return 1
      fi
      printf 'opencode --model %q\n' "$DEEPSEEK_MODEL"
      ;;
  esac
}

agent_available() {
  command_for "$1" >/dev/null
}

start_session() {
  local agent="$1"
  local command_line
  local inner_command

  tmux has-session -t "${agent}-main" 2>/dev/null && return 0

  if ! command_line="$(command_for "$agent")"; then
    echo "[router] $agent is unavailable. Install/authenticate it, or configure DEEPSEEK_MODEL for the DeepSeek route." >&2
    return 1
  fi

  inner_command="while true; do $command_line; exit_code=\$?; echo '[router] $agent exited with code ' \$exit_code; sleep 3; done"
  echo "[router] starting ${agent}-main"
  tmux new-session -d -s "${agent}-main" -c "$WORKDIR" "$inner_command"
}

capture_handoff() {
  local agent="$1"
  local handoff_file
  tmux has-session -t "${agent}-main" 2>/dev/null || return 0
  handoff_file="$ROUTER_DIR/handoff-${agent}-$(date -u +%Y%m%dT%H%M%SZ).log"
  tmux capture-pane -t "${agent}-main" -p -S -500 > "$handoff_file" || true
  echo "[router] saved ${agent} pane history to $handoff_file"
}

stop_session() {
  local agent="$1"
  tmux kill-session -t "${agent}-main" 2>/dev/null || true
}

next_available() {
  local exhausted="$1"
  local index=-1
  local offset
  local candidate

  for offset in "${!PRIORITY[@]}"; do
    [[ "${PRIORITY[$offset]}" == "$exhausted" ]] && index="$offset"
  done
  [[ "$index" -ge 0 ]] || index=-1

  for ((offset = 1; offset <= ${#PRIORITY[@]}; offset++)); do
    candidate="${PRIORITY[$(((index + offset) % ${#PRIORITY[@]}))]}"
    if [[ "$candidate" != "$exhausted" ]] && agent_available "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

use_agent() {
  local target="$1"
  local evicted

  valid_agent "$target" || { echo "Unknown agent: $target" >&2; return 2; }
  if ! agent_available "$target"; then
    echo "[router] $target is unavailable. Install/authenticate it, or configure DEEPSEEK_MODEL for the DeepSeek route." >&2
    return 1
  fi

  read_state
  if ! contains_active "$target"; then
    if [[ "${#ACTIVE[@]}" -ge "$MAX_ACTIVE" ]]; then
      evicted="${ACTIVE[0]}"
      echo "[router] maximum of $MAX_ACTIVE active agents; stopping $evicted"
      capture_handoff "$evicted"
      stop_session "$evicted"
      remove_active "$evicted"
    fi
    ACTIVE+=("$target")
  fi
  CURRENT="$target"
  write_state
  start_session "$target"
}

fallback_agent() {
  local exhausted="$1"
  local next

  valid_agent "$exhausted" || { echo "Unknown agent: $exhausted" >&2; return 2; }
  read_state
  contains_active "$exhausted" || { echo "$exhausted is not active" >&2; return 1; }

  if ! next="$(next_available "$exhausted")"; then
    echo "[router] no configured fallback is currently available" >&2
    return 1
  fi

  echo "[router] switching from $exhausted to $next"
  capture_handoff "$exhausted"
  stop_session "$exhausted"
  remove_active "$exhausted"
  if ! contains_active "$next"; then
    ACTIVE+=("$next")
  fi
  CURRENT="$next"
  write_state
  start_session "$next"
}

stop_agent() {
  local target="$1"

  valid_agent "$target" || { echo "Unknown agent: $target" >&2; return 2; }
  read_state
  contains_active "$target" || return 0
  capture_handoff "$target"
  stop_session "$target"
  remove_active "$target"
  if [[ "${#ACTIVE[@]}" -eq 0 ]]; then
    ACTIVE=(claude)
  fi
  CURRENT="${ACTIVE[${#ACTIVE[@]} - 1]}"
  write_state
  start_session "$CURRENT"
}

quota_detected() {
  local agent="$1"
  local pane

  tmux has-session -t "${agent}-main" 2>/dev/null || return 1
  pane="$(tmux capture-pane -t "${agent}-main" -p -S -1200 2>/dev/null || true)"
  printf '%s\n' "$pane" | grep -Eqi '(^|[^[:alnum:]])(usage limit (has been )?reached|quota (has been )?exceeded|rate limit exceeded|too many requests|you have reached .* (limit|quota))([^[:alnum:]]|$)'
}

reconcile() {
  local agent
  read_state
  for agent in "${ACTIVE[@]}"; do
    if quota_detected "$agent"; then
      echo "[router] detected a quota message for $agent"
      fallback_agent "$agent"
      return
    fi
  done
  for agent in "${ACTIVE[@]}"; do
    start_session "$agent" || true
  done
}

show_status() {
  local agent
  read_state
  echo "Current: $CURRENT"
  echo "Active (${#ACTIVE[@]}/$MAX_ACTIVE): ${ACTIVE[*]}"
  for agent in "${ALL_AGENTS[@]}"; do
    if tmux has-session -t "${agent}-main" 2>/dev/null; then
      echo "$agent: running"
    elif agent_available "$agent"; then
      echo "$agent: available, stopped"
    else
      echo "$agent: unavailable"
    fi
  done
}

attach_current() {
  read_state
  start_session "$CURRENT"
  ATTACH_SESSION="${CURRENT}-main"
}

monitor() {
  while true; do
    flock -x 9
    reconcile
    flock -u 9
    sleep 5
  done
}

command="${1:-status}"
case "$command" in
  use)
    [[ $# -eq 2 ]] || { echo "Usage: $0 use <agent>" >&2; exit 2; }
    flock -x 9; use_agent "$2"; flock -u 9
    ;;
  fallback)
    [[ $# -eq 2 ]] || { echo "Usage: $0 fallback <agent>" >&2; exit 2; }
    flock -x 9; fallback_agent "$2"; flock -u 9
    ;;
  stop)
    [[ $# -eq 2 ]] || { echo "Usage: $0 stop <agent>" >&2; exit 2; }
    flock -x 9; stop_agent "$2"; flock -u 9
    ;;
  status)
    flock -x 9; show_status; flock -u 9
    ;;
  attach)
    flock -x 9; attach_current; flock -u 9
    exec tmux new-session -A -s "$ATTACH_SESSION"
    ;;
  monitor)
    monitor
    ;;
  *)
    echo "Usage: $0 {use|fallback|stop|status|attach|monitor}" >&2
    exit 2
    ;;
esac
