#!/usr/bin/env bash
# Locks sshd down to Tailscale-only via ufw, with an automatic self-revert
# safety net -- so a mistake here can't actually lock you out.
#
# What went wrong the hard way, once, manually: verifying "the Tailscale
# rule works" from a second terminal BEFORE deleting the public "Anywhere"
# rule is the right instinct, but it's manual and easy to mess up (wrong
# shell, copy-pasted the wrong thing, network hiccup mid-verification).
# This script does the same add-then-delete sequence, but schedules an
# automatic revert a couple minutes later unless you explicitly confirm.
#
# Usage: run this ON the target node, as a user with (passwordless) sudo
# for the four ufw invocations below -- see the sudoers line printed if
# you don't have it yet.
#
#   ./scripts/harden-ssh-tailscale.sh          # apply + arm the revert timer
#   touch /tmp/.ssh-hardening-confirmed        # cancel the revert once verified

set -euo pipefail

REVERT_DELAY="${REVERT_DELAY:-120}"
TAILSCALE_V4_CIDR="100.64.0.0/10"
TAILSCALE_V6_CIDR="fd7a:115c:a1e0::/48"
CONFIRM_FILE="/tmp/.ssh-hardening-confirmed"
REVERT_LOG="/tmp/.ssh-hardening-revert.log"

if ! sudo -n -l 2>/dev/null | grep -q "ufw delete allow OpenSSH"; then
  cat >&2 << EOF
Missing passwordless sudo for the ufw commands this script needs. Add:

  sudo bash -c 'cat >> /etc/sudoers.d/claude-watchdog << SUDOERS
$(whoami) ALL=(root) NOPASSWD: /usr/sbin/ufw allow from ${TAILSCALE_V4_CIDR} to any port 22 proto tcp comment tailscale-ssh
$(whoami) ALL=(root) NOPASSWD: /usr/sbin/ufw allow from ${TAILSCALE_V6_CIDR} to any port 22 proto tcp comment tailscale-ssh-v6
$(whoami) ALL=(root) NOPASSWD: /usr/sbin/ufw delete allow OpenSSH
$(whoami) ALL=(root) NOPASSWD: /usr/sbin/ufw allow OpenSSH
SUDOERS'

then re-run this script.
EOF
  exit 1
fi

rm -f "$CONFIRM_FILE" "$REVERT_LOG"

echo "==> Allowing SSH from Tailscale only (v4 + v6)"
sudo ufw allow from "$TAILSCALE_V4_CIDR" to any port 22 proto tcp comment 'tailscale-ssh'
sudo ufw allow from "$TAILSCALE_V6_CIDR" to any port 22 proto tcp comment 'tailscale-ssh-v6'

echo "==> Removing the public 'Anywhere' rule (if present)"
sudo ufw delete allow OpenSSH || echo "  (already removed, or never existed under that name -- continuing)"

echo "==> Arming a ${REVERT_DELAY}s auto-revert safety net"
nohup bash -c "
  sleep '$REVERT_DELAY'
  if [[ ! -f '$CONFIRM_FILE' ]]; then
    sudo ufw allow OpenSSH
    echo \"\$(date -u +%FT%TZ) reverted: public SSH re-allowed, no confirmation in time\" >> '$REVERT_LOG'
  fi
" > /tmp/.ssh-hardening-nohup.log 2>&1 &
disown

cat << EOF

Done. Public SSH is now blocked; Tailscale-sourced SSH should still work.

VERIFY NOW from a SEPARATE terminal/machine (not this session):
  ssh -o RemoteCommand=none <your-tailscale-alias> echo ok

If that works, confirm within ${REVERT_DELAY}s to cancel the auto-revert:
  touch $CONFIRM_FILE

If you DON'T confirm in time, the public 'Anywhere' rule is automatically
restored (check $REVERT_LOG afterward) -- you cannot get permanently
locked out by this script.
EOF
