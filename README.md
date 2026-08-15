# agent-outpost

Always-on AI coding CLIs, running headless in separate tmux sessions on a box
you own, reachable from any client over Tailscale. The laptop becomes a dummy
terminal into a long-running session -- closing the lid or losing wifi doesn't
kill anything.

(Formerly named "homelab" -- renamed since this runs equally well on a
cloud VPS as literal home hardware, and the old name implied otherwise.
Deployed nodes still use `~/homelab` as their working directory internally,
purely for path stability across existing and future setups -- that's an
implementation detail, not a naming decision.)

```
[client: laptop/phone] --ssh over Tailscale--> [server: independently watched tmux sessions] --> [Claude | Codex | Hermes | Kimi | OpenCode | Agy]
```

## Components

- `Makefile` -- orchestrates everything below from your laptop (`make help`
  for the full list, `make setup` to run it all in order on a new node).
- `scripts/bootstrap-node.sh` -- idempotent setup for a fresh box: tmux,
  Tailscale, Node, Claude Code, Codex, Hermes, Kimi Code, OpenCode, and their
  watchdog systemd services. Agy is enabled when its native Linux CLI is
  present; Ollama is deliberately installed separately and never downloads a
  model automatically.
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
- `scripts/agent-watchdog.sh` and the Hermes, Kimi, OpenCode, and Agy systemd
  units -- one isolated `*-main` tmux session per CLI, with the same restart
  guarantees as Claude and Codex.
- `scripts/install-ollama.sh` -- an explicit Ollama-server install. It starts
  no model and does not change model storage until you request a model.
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
make attach-hermes  # Hermes
make attach-kimi    # Kimi Code
make attach-opencode # OpenCode
make connect-deepseek # OpenCode's DeepSeek provider flow
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

Hermes, Kimi Code, and OpenCode similarly keep their provider login state in
the node user's home directory. Attach to each newly created session once and
complete the CLI's own sign-in/setup flow; do not copy local config folders or
API keys onto the node. Store any new provider credentials in 1Password before
placing them in the node's environment. Agy follows the same pattern once its
vendor-provided x86_64 Linux launcher is installed at `~/.local/bin/agy`.

DeepSeek is available in OpenCode as a built-in provider rather than as a
separate watchdog-managed CLI. After OpenCode is installed, run
`make connect-deepseek`; in the OpenCode UI, use `/connect` to select
**DeepSeek**, complete its key prompt, then use `/models` to select the model.
Create and store a new key in 1Password before entering it there; the key is
kept in the node user's OpenCode credential store, never in this repository.

## Switch agents and use ChatGPT Remote

Claude and Codex run independently. If one harness is unavailable or you want
to try the other agent, attach to the matching session:

```bash
make attach         # Claude (`chome`)
make attach-codex   # Codex (`cohome`)
make attach-hermes  # Hermes
make attach-kimi    # Kimi Code
make attach-opencode # OpenCode
make attach-agy     # Agy, after its native Linux CLI is installed
make connect-deepseek # OpenCode's DeepSeek provider
```

### Use the models together, safely

The harness keeps each session alive, but it does **not** make concurrent edits
to one checkout safe. Give one agent ownership of implementation at a time;
use the others for planning, research, tests, or review. For parallel coding,
create a separate git worktree per agent and start that agent from its own
worktree.

| Session | Good role |
| --- | --- |
| `claude-main`, `codex-main` | Primary implementation and issue recovery |
| `hermes-main`, `kimi-main` | Independent planning, exploration, and review |
| `opencode-main` | Provider-agnostic alternate coding workflow |
| DeepSeek in `opencode-main` | DeepSeek coding/reasoning models via `/connect` and `/models` |
| `agy-main` | Your configured Agy model pool, after installing its Linux CLI |
| Ollama + OpenCode | Private/local or self-hosted models, when the host has enough RAM |

Ollama is intentionally a separate opt-in because model files and runtime RAM
are substantial. On the current 4 GB outpost node, do not pull a model until
you have increased capacity or pointed OpenCode at a stronger Ollama host:

```bash
make ollama-install                 # installs the server only
make ollama-status                  # verifies service and lists local models
make ollama-pull MODEL=<model-name> # explicit model download
```

OpenCode can then be configured through its provider flow, including an Ollama
endpoint. No model is selected or downloaded by this repository.

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

The same three layers apply independently to Codex, Hermes, Kimi, OpenCode,
and (once installed) Agy. The Codex remote-control app-server uses Codex's own
durable manager and is deliberately separate from the interactive tmux session.

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
