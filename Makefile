.PHONY: help env ssh-config terminfo bootstrap harden status attach setup

help:
	@echo "homelab -- always-on Claude Code, orchestrated"
	@echo ""
	@echo "First time on a new node:"
	@echo "  make setup        Do everything below, in order"
	@echo ""
	@echo "Individual steps:"
	@echo "  make env          Create .env from .env.example if missing (then edit it!)"
	@echo "  make ssh-config   Add the claude-home Host block + chome alias, locally"
	@echo "  make bootstrap    Push this repo to the node and run bootstrap-node.sh there"
	@echo "  make harden       Lock the node's SSH to Tailscale-only (self-reverting)"
	@echo "  make terminfo     Push your terminal's terminfo entry to the node"
	@echo "  make status       Show the watchdog service + tmux session status"
	@echo "  make attach       Connect and attach to the live session"

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
		./scripts/gen-ssh-config.sh >> ~/.ssh/config && echo "Added claude-home to ~/.ssh/config"; \
	fi
	@if grep -q 'alias chome=' ~/.zshrc 2>/dev/null; then \
		echo "chome alias already in ~/.zshrc, skipping"; \
	else \
		echo 'alias chome="ssh claude-home"' >> ~/.zshrc && echo "Added chome alias to ~/.zshrc (run: source ~/.zshrc)"; \
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
		"sudo systemctl status claude-watchdog@$$HOMELAB_SSH_USER.service --no-pager; echo; tmux capture-pane -t claude-main -p | tail -10"

attach:
	ssh -t claude-home

setup: env ssh-config bootstrap harden terminfo
	@echo ""
	@echo "Done. Run 'make attach' or (after 'source ~/.zshrc') just 'chome' to connect."
