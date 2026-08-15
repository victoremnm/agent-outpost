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
[client: laptop/phone] --ssh over Tailscale--> [router: at most two tmux sessions] --> [selected model]
```

## Components

- `Makefile` -- orchestrates everything below from your laptop (`make help`
  for the full list, `make setup` to run it all in order on a new node).
- `scripts/bootstrap-node.sh` -- idempotent setup for a fresh box: tmux,
  Tailscale, Node, Claude Code, Codex, Hermes, Kimi Code, OpenCode, and their
  router service. Agy is selectable when its native Linux CLI is present;
  Ollama is deliberately installed separately and never downloads a model
  automatically.
- `scripts/harden-ssh-tailscale.sh` -- locks the node's SSH down to
  Tailscale-only, with an automatic self-revert if you don't confirm it
  worked within 2 minutes (see "Security" below).
- `scripts/install-client-terminfo.sh` -- pushes your terminal's terminfo
  entry to the node, fixing `missing or unsuitable terminal` errors with
  newer terminal emulators (Ghostty, WezTerm, kitty).
- `scripts/agent-router.sh` and `systemd/agent-router@.service` -- keep the
  selected interactive sessions alive, enforce a maximum of two live agents,
  and advance an exhausted agent to the next available provider. Pane history
  is saved before a router-initiated switch.
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

Before it installs the additional agent CLIs, bootstrap requires at least
1 GiB of currently available RAM. This prevents a dependency install from
overcommitting a busy node and dropping its SSH connection. Free memory or
resize the node first if it stops at that guard; this is separate from the
substantially higher capacity needed to run local Ollama models.

Already set up and just want to connect?

```bash
make route-status               # see current and active routes
make attach                     # attach to the current route
make route-use AGENT=codex      # add/select Codex (max. two remain live)
```

## Auth model

The router runs `claude` with no `ANTHROPIC_API_KEY` set, so it uses
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

DeepSeek is an OpenCode-backed route rather than a second heavyweight CLI.
Run `make connect-deepseek`, use `/connect` to select **DeepSeek**, and use
`/models` to find its `provider/model` ID. Create and store a new key in
1Password before entering it there; the key remains in the node user's
OpenCode credential store, never in this repository.

## Route agents and use ChatGPT Remote

The router keeps **one or two** agents live, never every installed CLI. Its
default fallback order is:

```bash
claude -> codex -> opencode -> agy -> kimi -> deepseek
```

Hermes is deliberately outside that automatic route but remains selectable
with `make route-use AGENT=hermes`.

```bash
make route-status
make route-use AGENT=codex       # select Codex; with two live sessions, evicts the oldest
make route-fallback AGENT=codex  # force Codex -> OpenCode
make route-stop AGENT=opencode   # stop a route and free its slot
make attach                      # always attaches to the router's current route
```

The router checks active panes for specific quota/rate-limit errors every five
seconds and automatically applies the same fallback. It saves the last 500
lines of the exhausted pane to `~/.agent-outpost/router/handoff-*.log` before
stopping it. Use `make route-fallback AGENT=<agent>` if a provider shows a
quota message the CLI renders in a form the router cannot recognize.

There is no safe way for one vendor CLI to inherit another CLI's full live
conversation or tool state. Treat the saved handoff as the bridge: attach to
the new route and give it the relevant summary or task. The router does
preserve the original CLI's own persisted session for later resumption.

To make DeepSeek eligible for automatic fallback after completing its OpenCode
login, set the model ID you selected:

```bash
make route-configure-deepseek MODEL=<provider/model>
```

### Use the models safely

The harness keeps each session alive, but it does **not** make concurrent edits
to one checkout safe. Give one agent ownership of implementation at a time;
use the others for planning, research, tests, or review. For parallel coding,
create a separate git worktree per agent and start that agent from its own
worktree.

| Session | Good role |
| --- | --- |
| `claude-main`, `codex-main` | Highest-priority implementation and recovery |
| `opencode-main`, `agy-main`, `kimi-main` | Ordered fallbacks |
| `deepseek-main` | OpenCode with your configured DeepSeek model |
| `hermes-main` | Explicitly selected, outside the automatic order |
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

The router has three layers of recovery:

1. Each selected session has an inner restart loop: a CLI process crash or
   exit restarts it in the same pane within 3 seconds.
2. The router monitor recreates a selected tmux session within 5 seconds if
   the tmux server or session dies.
3. `systemd` `Restart=always` + `enable` brings the router back after a host
   reboot or router process failure.

The Codex remote-control app-server uses Codex's own durable manager and is
deliberately separate from the router's interactive Codex session.

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
