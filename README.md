# homelab

Always-on Claude Code, running headless in tmux on a box you own, reachable
from any client over Tailscale. The laptop becomes a dummy terminal into a
long-running session -- closing the lid or losing wifi doesn't kill anything.

```
[client: laptop/phone] --ssh over Tailscale--> [server: tmux session] --> [claude, watched]
```

## Components

- `scripts/bootstrap-node.sh` -- idempotent setup for a fresh box: tmux,
  Tailscale, Node, Claude Code CLI, and the watchdog systemd service.
- `scripts/claude-watchdog.sh` -- the loop that keeps a tmux session named
  `claude-main` alive with `claude` running inside it. If `claude` exits or
  crashes, it restarts in the same pane within 3s. If the whole tmux server
  dies, the loop recreates the session within 10s.
- `systemd/claude-watchdog@.service` -- template unit (`claude-watchdog@<user>.service`)
  that runs the watchdog under systemd with `Restart=always`, so it also
  survives a full host reboot once enabled.
- `scripts/ssh-config-snippet.txt` -- `~/.ssh/config` block for quick
  `ssh claude-home` access from any client on the tailnet.
- `.claude/skills/homelab-bootstrap/` -- a Claude Code skill that walks
  through provisioning a new node from this repo end to end.

## Quick start on a new machine

```bash
git clone <this repo> ~/homelab
cd ~/homelab
sudo tailscale up          # if not already on the tailnet
./scripts/bootstrap-node.sh
tmux attach -t claude-main # one-time: log in when prompted, then ctrl-b d
```

From any other machine on the tailnet, one-time setup with
`scripts/ssh-config-snippet.txt`, then just:

```bash
chome   # or: ssh claude-home
```

Without that setup, the manual equivalent is:

```bash
ssh <user>@<tailscale-ip-or-magicdns-name> -t tmux attach -t claude-main
```

## Auth model

The watchdog runs `claude` with no `ANTHROPIC_API_KEY` set, so it uses
interactive OAuth login (your Claude subscription, not API billing). Do the
login once per box, inside the tmux pane -- the resulting token persists in
`~/.claude/` and auto-refreshes. If you'd rather bill per-token via the API
instead, export `ANTHROPIC_API_KEY` in the systemd unit's `Environment=` line
and skip the interactive login.

## Restart guarantees

Three layers, each catching a different failure:

1. Inner `while true; do claude; done` loop -- `claude` process crashes or
   exits -> restarts in the same tmux pane in 3s.
2. Watchdog's outer loop -- the tmux server itself dies -> session recreated
   within 10s.
3. `systemd` `Restart=always` + `enable` -- the watchdog script itself dies,
   or the host reboots -> service comes back automatically.

## Known hosts

| Host | Tailscale IP | Notes |
|---|---|---|
| ubuntu-s-2vcpu-4gb-sfo2-01 (DigitalOcean VPS) | 0.0.0.0 | Primary always-on node |
