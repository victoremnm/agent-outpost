#!/usr/bin/env bash
# Prints the ~/.ssh/config Host block for your node, filled in from .env.
# ssh_config can't read a .env file directly, so this generates the literal
# block for you to append -- keeps the real address out of tracked files.
#
# Usage:
#   cp .env.example .env && edit it with your node's real values
#   ./scripts/gen-ssh-config.sh >> ~/.ssh/config

set -euo pipefail

ENV_FILE="$(dirname "$0")/../.env"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "No .env found. Run: cp .env.example .env, then fill in your values." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

: "${HOMELAB_TAILSCALE_IP:?missing HOMELAB_TAILSCALE_IP in .env}"
: "${HOMELAB_SSH_USER:?missing HOMELAB_SSH_USER in .env}"

cat << EOF

Host claude-home
  HostName ${HOMELAB_TAILSCALE_IP}
  User ${HOMELAB_SSH_USER}
  RequestTTY yes
  RemoteCommand tmux new-session -A -s claude-main
EOF
