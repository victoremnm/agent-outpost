# agent-outpost

Always-on Claude Code and Codex CLI, running headless in separate tmux sessions
on a box you own, reachable from any client over Tailscale. The laptop becomes a
dummy terminal into a long-running session -- closing the lid or losing wifi
doesn't kill anything.

(Formerly named "homelab" -- renamed since this runs equally well on a
cloud VPS as literal home hardware, and the old name implied otherwise.
Deployed nodes still use `~/homelab` as their working directory internally,
purely for path stability across existing and future setups -- that's an
implementation detail, not a naming decision.)

```
[client: laptop/phone] --ssh over Tailscale--> [server: tmux sessions] --> [claude | codex, watched]
```

## Components

- `Makefile` -- orchestrates everything below from your laptop (`make help`
  for the full list, `make setup` to run it all in order on a new node).
- `scripts/bootstrap-node.sh` -- idempotent setup for a fresh box: tmux,
  Tailscale, Node, Claude Code CLI, Codex CLI, and watchdog systemd services.
- `scripts/harden-ssh-tailscale.sh` -- locks the node's SSH down to
  Tailscale-only, with an automatic self-revert if you don't confirm it
  worked within 2 minutes (see "Security" below).
- `scripts/install-client-terminfo.sh` -- pushes your terminal's terminfo
  entry to the node, fixing `missing or unsuitable terminal` errors with
  newer terminal emulators (Ghostty, WezTerm, kitty).
- `scripts/claude-watchdog.sh` -- the loop that keeps a tmux session named
  `claude-main` alive with `claude` running inside it. If `claude` exits or
  crashes, it restarts in the same pane within 3s. If the whole tmux server
  dies, the loop recreates the session within 10s.
- `systemd/claude-watchdog@.service` -- template unit (`claude-watchdog@<user>.service`)
  that runs the watchdog under systemd with `Restart=always`, so it also
  survives a full host reboot once enabled.
- `scripts/codex-watchdog.sh` and `systemd/codex-watchdog@.service` -- the
  equivalent independently watched `codex-main` session. Codex's app-server
  daemon is managed by Codex, not by this tmux watchdog.
- `scripts/gen-ssh-config.sh` -- generates the `~/.ssh/config` block for
  quick `ssh claude-home` access from any client on the tailnet, filled in
  from your local `.env` (never committed).
- `.claude/skills/agent-outpost-bootstrap/` -- a Claude Code skill that walks
  through provisioning a new node from this repo end to end.
- `.env.example` -- copy to `.env` and fill in your own node's Tailscale IP,
  SSH user, and hostname. `.env` is gitignored -- real addresses never get
  committed, which matters if this repo is ever public.

## Quick start on a new node

From your laptop (not the node), with the node already reachable over SSH
and Tailscale up on both ends:

```bash
git clone <this repo> ~/Code/Repositories/agent-outpost
cd ~/Code/Repositories/agent-outpost
make env        # copies .env.example -> .env; fill in the node's real
                 # Tailscale IP + SSH user before continuing
make setup       # ssh-config + push repo + bootstrap-node.sh + harden + terminfo
```

`make setup` runs each step in order (see `make help` for them individually)
and pushes this repo to the node via `rsync`, so the node doesn't need git
credentials for a private repo. The one manual part it can't automate: the
one-time interactive Claude Code OAuth login (`make attach`, then follow the
prompt, then `ctrl-b d` to detach) and confirming the SSH hardening within
its revert window (see "Security" below).

Already set up and just want to connect?

```bash
make attach         # Claude, or `chome` after `make ssh-config` + `source ~/.zshrc`
make attach-codex   # Codex, or `cohome`
```

## Auth model

The watchdog runs `claude` with no `ANTHROPIC_API_KEY` set, so it uses
interactive OAuth login (your Claude subscription, not API billing). Do the
login once per box, inside the tmux pane -- the resulting token persists in
`~/.claude/` and auto-refreshes. If you'd rather bill per-token via the API
instead, export `ANTHROPIC_API_KEY` in the systemd unit's `Environment=` line
and skip the interactive login.

Codex is also installed without `OPENAI_API_KEY`. Sign in once inside the
`codex-main` tmux pane using **Sign in with ChatGPT**; that uses the Codex
access included with your ChatGPT plan rather than usage-based API billing.
Do not add an API key unless you intentionally want API-priced usage.

## Switch agents and use ChatGPT Remote

Claude and Codex run independently. If one harness is unavailable or you want
to try the other agent, attach to the matching session:

```bash
make attach         # Claude (`chome`)
make attach-codex   # Codex (`cohome`)
```

After signing in to Codex once, enable its durable SSH app-server with remote
control:

```bash
make remote-control
```

To receive and steer Codex work in the ChatGPT mobile app, use the official
Remote flow: on a Mac or Windows machine with the ChatGPT desktop app, add
`codex-home` from `~/.ssh/config` in **Settings > Connections**, select a
project on the node, then pair that desktop host with the ChatGPT mobile app.
The desktop app starts and manages the remote Codex app-server over SSH; no
port is opened on the node. Keep that desktop host awake and online while using
the mobile app.

## Restart guarantees

Three layers, each catching a different failure:

1. Inner `while true; do claude; done` loop -- `claude` process crashes or
   exits -> restarts in the same tmux pane in 3s.
2. Watchdog's outer loop -- the tmux server itself dies -> session recreated
   within 10s.
3. `systemd` `Restart=always` + `enable` -- the watchdog script itself dies,
   or the host reboots -> service comes back automatically.

The same three layers apply independently to Codex. The Codex remote-control
app-server uses Codex's own durable manager and is deliberately separate from
the interactive tmux session.

## Known hosts

Real hostnames and Tailscale IPs live in your local `.env` (gitignored), not
here -- this file is committed and, eventually, public.

## Security

- **SSH is Tailscale-only.** `scripts/harden-ssh-tailscale.sh` locks `sshd`
  down via `ufw` so port 22 only accepts connections sourced from the
  tailnet (`100.64.0.0/10` + its IPv6 range) -- the public IP refuses SSH
  entirely. It arms a 2-minute auto-revert: if you don't confirm the
  Tailscale path actually works (`touch /tmp/.ssh-hardening-confirmed`),
  the public rule comes back automatically. This exists because verifying
  "did the new rule actually work" by hand, before deleting the fallback,
  is exactly the kind of step that's easy to skip or get wrong under
  pressure -- the script makes skipping it safe instead of risky.
- **Sudo is narrowly scoped**, not blanket `NOPASSWD: ALL`. Each node's
  `/etc/sudoers.d/claude-watchdog` grants exactly the commands the watchdog
  and hardening scripts need (service management, one specific file copy,
  the four `ufw` invocations above) -- nothing else. Check what's granted
  with `sudo -n -l`.
- **Terminal type mismatches**: newer terminal emulators (Ghostty, WezTerm,
  kitty) set a `$TERM` that minimal Linux boxes don't have a terminfo entry
  for, causing tmux to refuse to start with `missing or unsuitable
  terminal`. Fix with `scripts/install-client-terminfo.sh <host>`, run from
  the client whose terminal is affected.
- **Running one-off commands against a node**: since `~/.ssh/config`'s
  `RemoteCommand` makes plain `ssh claude-home` auto-attach to tmux, pass
  `-o RemoteCommand=none` to run an actual command instead of attaching,
  e.g. `ssh -o RemoteCommand=none claude-home "some command"`.
