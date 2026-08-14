---
name: homelab-bootstrap
description: Provision a new always-on Claude Code host (SBC or VPS) using the scripts in this repo -- tmux + Tailscale + systemd watchdog. Use when the user says "set up a new homelab node", "add another always-on Claude box", or "bootstrap this server for Claude Code".
---

# homelab-bootstrap

Provisions a fresh Linux box into an always-on Claude Code host: a tmux
session named `claude-main` running `claude`, watched by a loop, wrapped in
a systemd service, reachable over Tailscale from any client.

## When invoked

1. **Get target details from the user**: hostname/IP, SSH user, and whether
   it already has Tailscale/tmux/Node installed. Don't assume -- ask if
   unclear whether this is a fresh box or already partially set up.
2. **Confirm auth model** (see README.md "Auth model"): interactive OAuth
   (subscription billing, needs a one-time manual login step) vs
   `ANTHROPIC_API_KEY` (fully non-interactive, API billing). If API key,
   check 1Password for an existing valid key before asking the user to
   paste one in plaintext -- store any new key in 1Password immediately
   per the user's global secrets-management convention.
3. **Check sudo access**: passwordless sudo is not assumed. If sudo needs a
   password, hand the user the exact command to run themselves rather than
   asking for their password directly. Prefer a scoped sudoers rule
   (`NOPASSWD` for `/usr/bin/systemctl` and `/usr/bin/apt-get` only) over
   blanket `NOPASSWD: ALL`.
4. **Clone this repo onto the target** at `~/homelab`, then run
   `scripts/bootstrap-node.sh`. This is idempotent -- safe to re-run if a
   step fails partway.
5. **Enable + start** `claude-watchdog@<user>.service`, verify with
   `systemctl status`.
6. **One-time interactive login**: `tmux attach -t claude-main` and walk the
   user through the OAuth prompt if that's the chosen auth model (skip if
   using an API key). Remind them to `ctrl-b d` to detach, not `exit`/`ctrl-c`.
7. **Verify from a second client**: SSH in from a different machine (or the
   same one via a fresh connection) and confirm `tmux attach -t claude-main`
   reconnects to a live, already-logged-in session.
8. **Never commit the new node's real hostname/IP.** Add it to the user's
   local `.env` (gitignored) instead of any tracked file -- this repo is
   intended to go public eventually. If a change to a tracked file is
   needed, commit on a feature branch and open a PR as usual, but keep the
   actual address out of it.

## Guardrails

- Never install a blanket `NOPASSWD: ALL` sudo rule without asking first --
  scope it to the specific commands the watchdog setup needs.
- Never put an API key in plaintext in the systemd unit file if it can go
  in 1Password + be read into the environment at service start instead.
- This provisions infrastructure the user will rely on long-term -- confirm
  the target host before running anything destructive-adjacent (package
  installs are fine and reversible; don't touch existing tmux sessions or
  systemd units unrelated to this setup without checking what they are
  first).
