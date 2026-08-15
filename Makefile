.PHONY: help env ssh-config terminfo bootstrap harden status attach attach-codex remote-control setup

help:
	@echo "agent-outpost -- always-on Claude Code and Codex CLI, orchestrated"
	@echo ""
	@echo "First time on a new node:"
	@echo "  make setup        Do everything below, in order"
	@echo ""
	@echo "Individual steps:"
	@echo "  make env          Create .env from .env.example if missing (then edit it!)"
	@echo "  make ssh-config   Add Claude/Codex SSH host blocks and chome/cohome aliases, locally"
	@echo "  make bootstrap    Push this repo to the node and run bootstrap-node.sh there"
	@echo "  make harden       Lock the node's SSH to Tailscale-only (self-reverting)"
	@echo "  make terminfo     Push your terminal's terminfo entry to the node"
	@echo "  make status       Show both watchdog services and tmux sessions"
	@echo "  make attach       Connect to the live Claude session"
	@echo "  make attach-codex Connect to the live Codex session"
	@echo "  make remote-control  Enable Codex's durable SSH app-server for ChatGPT Remote"

env:
	@if [ -f .env ]; then \
		echo ".env already exists, skipping"; \
	else \
		cp .env.example .env; \
		echo "Created .env -- edit it with your node's real HOMELAB_TAILSCALE_IP / HOMELAB_SSH_USER before running other targets"; \
	fi

ssh-config: env
	@. ./.env && \
	if grep -q "^Host claude-home$$" ~/.ssh/config 2>/dev/null; then \
		echo "claude-home already in ~/.ssh/config, skipping"; \
	else \
		./scripts/gen-ssh-config.sh claude >> ~/.ssh/config && echo "Added claude-home to ~/.ssh/config"; \
	fi
	@. ./.env && \
	if grep -q "^Host codex-home$$" ~/.ssh/config 2>/dev/null; then \
		echo "codex-home already in ~/.ssh/config, skipping"; \
	else \
		./scripts/gen-ssh-config.sh codex >> ~/.ssh/config && echo "Added codex-home to ~/.ssh/config"; \
	fi
	@if grep -q 'alias chome=' ~/.zshrc 2>/dev/null; then \
		echo "chome alias already in ~/.zshrc, skipping"; \
	else \
		echo 'alias chome="ssh claude-home"' >> ~/.zshrc && echo "Added chome alias to ~/.zshrc (run: source ~/.zshrc)"; \
	fi
	@if grep -q 'alias cohome=' ~/.zshrc 2>/dev/null; then \
		echo "cohome alias already in ~/.zshrc, skipping"; \
	else \
		echo 'alias cohome="ssh -t codex-home tmux new-session -A -s codex-main"' >> ~/.zshrc && echo "Added cohome alias to ~/.zshrc (run: source ~/.zshrc)"; \
	fi

bootstrap: env
	@. ./.env && \
	echo "==> Pushing repo to $$HOMELAB_SSH_USER@$$HOMELAB_TAILSCALE_IP:~/homelab" && \
	ssh -o RemoteCommand=none "$$HOMELAB_SSH_USER@$$HOMELAB_TAILSCALE_IP" "mkdir -p ~/homelab" && \
	rsync -az --exclude .git --exclude .env . "$$HOMELAB_SSH_USER@$$HOMELAB_TAILSCALE_IP:~/homelab/" && \
	ssh -t -o RemoteCommand=none "$$HOMELAB_SSH_USER@$$HOMELAB_TAILSCALE_IP" \
		"chmod +x ~/homelab/scripts/*.sh && cd ~/homelab && ./scripts/bootstrap-node.sh"

harden: env
	@. ./.env && \
	ssh -t -o RemoteCommand=none "$$HOMELAB_SSH_USER@$$HOMELAB_TAILSCALE_IP" \
		"cd ~/homelab && ./scripts/harden-ssh-tailscale.sh"

terminfo: env
	./scripts/install-client-terminfo.sh claude-home

status: env
	@. ./.env && \
	ssh -o RemoteCommand=none "$$HOMELAB_SSH_USER@$$HOMELAB_TAILSCALE_IP" \
		"sudo systemctl status claude-watchdog@$$HOMELAB_SSH_USER.service codex-watchdog@$$HOMELAB_SSH_USER.service --no-pager; echo; tmux capture-pane -t claude-main -p | tail -10; echo; tmux capture-pane -t codex-main -p | tail -10"

attach:
	ssh -t claude-home

attach-codex:
	ssh -t codex-home tmux new-session -A -s codex-main

remote-control: env
	@. ./.env && \
	ssh -t -o RemoteCommand=none "$$HOMELAB_SSH_USER@$$HOMELAB_TAILSCALE_IP" \
		'export PATH="$$HOME/.local/bin:$$PATH"; codex app-server daemon bootstrap --remote-control'

setup: env ssh-config bootstrap harden terminfo
	@echo ""
	@echo "Done. Run 'make attach' / 'make attach-codex' or (after 'source ~/.zshrc') 'chome' / 'cohome' to connect."
