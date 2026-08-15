---
name: homelab-bootstrap
description: Provision a new always-on Claude Code host (SBC or VPS) using the scripts in this repo -- tmux + Tailscale + systemd watchdog. Use when the user says "set up a new homelab node", "add another always-on Claude box", or "bootstrap this server for Claude Code".
---

# homelab-bootstrap

Provisions a fresh Linux box into an always-on Claude Code host: a tmux
session named `claude-main` running `claude`, watched by a loop, wrapped in
a systemd service, reachable over Tailscale from any client.

## When invoked

The `Makefile` orchestrates most of this -- prefer it over running scripts
by hand. `make help` lists every step; `make setup` runs them all in order.

1. **Get target details from the user**: hostname/IP, SSH user, and whether
   it already has Tailscale/tmux/Node installed. Don't assume -- ask if
   unclear whether this is a fresh box or already partially set up.
2. **Confirm auth model** (see README.md "Auth model"): interactive OAuth
   (subscription billing, needs a one-time manual login step) vs
   `ANTHROPIC_API_KEY` (fully non-interactive, API billing). If API key,
   check 1Password for an existing valid key before asking the user to
   paste one in plaintext -- store any new key in 1Password immediately
   per the user's global secrets-management convention.
3. **`make env`**, then have the user fill in `.env` with the real node
   address before continuing -- everything downstream depends on it.
4. **Check sudo access**: passwordless sudo is not assumed. If sudo needs a
   password, hand the user the exact command to run themselves rather than
   asking for their password directly. Prefer a scoped sudoers rule
   (`NOPASSWD` for the specific commands each script needs -- see
   README.md "Security" for the current list) over blanket `NOPASSWD: ALL`.
5. **`make bootstrap`** -- pushes this repo to the target via `rsync` (no
   git credentials needed on a fresh box) and runs `scripts/bootstrap-node.sh`
   there. Idempotent -- safe to re-run if a step fails partway.
6. **`make ssh-config`** on the user's client, so `make attach` / `chome`
   work going forward.
7. **One-time interactive login**: `make attach` and walk the user through
   the OAuth prompt if that's the chosen auth model (skip if using an API
   key). Remind them to `ctrl-b d` to detach, not `exit`/`ctrl-c`.
8. **Verify from a second client**: SSH in from a different machine (or the
   same one via a fresh connection) and confirm `make attach` (or
   `chome`) reconnects to a live, already-logged-in session.
9. **Never commit the new node's real hostname/IP.** It only ever lives in
   `.env` (gitignored) -- this repo is intended to go public eventually. If
   a change to a tracked file is needed, commit on a feature branch and
   open a PR as usual, but keep the actual address out of it.
10. **`make harden`** locks SSH to Tailscale-only. It self-verifies with an
    auto-revert (see README.md "Security") -- still walk the user through
    confirming from a second client within the revert window rather than
    assuming it worked.
11. **`make terminfo`** if the user's client uses a less common terminal
    (Ghostty, WezTerm, kitty) -- avoids the `missing or unsuitable
    terminal` surprise on first connect.

## Guardrails

- Never install a blanket `NOPASSWD: ALL` sudo rule without asking first --
  scope it to the specific commands the watchdog setup needs. IPv6 CIDRs
  in a sudoers command argument need each `:` backslash-escaped
  (`fd7a\:115c\:a1e0\:\:/48`), not shell-quoted -- sudoers has its own
  lexer, separate from the shell. Always validate with `visudo -cf` before
  trusting a sudoers edit.
- Never put an API key in plaintext in the systemd unit file if it can go
  in 1Password + be read into the environment at service start instead.
- This provisions infrastructure the user will rely on long-term -- confirm
  the target host before running anything destructive-adjacent (package
  installs are fine and reversible; don't touch existing tmux sessions or
  systemd units unrelated to this setup without checking what they are
  first).
- Before removing any fallback access path (like a public SSH rule), verify
  the replacement works from a genuinely separate connection first -- or
  use a script with an auto-revert like `harden-ssh-tailscale.sh` so a
  verification mistake can't cause a lasting lockout.
- When running commands against a node whose SSH config has a
  `RemoteCommand` (e.g. for tmux auto-attach), pass
  `-o RemoteCommand=none` to run one-off commands instead of attaching.
