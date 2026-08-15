.PHONY: help env ssh-config terminfo bootstrap harden status attach attach-codex attach-agent attach-agy attach-hermes attach-kimi attach-opencode connect-deepseek remote-control ollama-install ollama-status ollama-pull setup

help:
	@echo "agent-outpost -- always-on multi-agent CLI harness, orchestrated"
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
	@echo "  make status       Show watchdog services and tmux sessions"
	@echo "  make attach       Connect to the live Claude session"
	@echo "  make attach-codex Connect to the live Codex session"
	@echo "  make attach-hermes / attach-kimi / attach-opencode / attach-agy"
	@echo "                    Connect to an additional agent session"
	@echo "  make connect-deepseek  Attach OpenCode and add/select DeepSeek interactively"
	@echo "  make remote-control  Enable Codex's durable SSH app-server for ChatGPT Remote"
	@echo "  make ollama-install  Install Ollama's server only (does not pull a model)"
	@echo "  make ollama-status   Show the node's Ollama service and installed models"
	@echo "  make ollama-pull MODEL=<model>  Explicitly download an Ollama model"

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
		"for agent in claude codex agy hermes kimi opencode; do echo \"==> \$$agent watchdog\"; sudo systemctl status \"\$$agent-watchdog@$$HOMELAB_SSH_USER.service\" --no-pager || true; echo; if tmux has-session -t \"\$$agent-main\" 2>/dev/null; then tmux capture-pane -t \"\$$agent-main\" -p | tail -10; else echo \"No \$$agent-main tmux session\"; fi; echo; done; echo '==> Ollama'; sudo systemctl status ollama.service --no-pager || true; ollama list 2>/dev/null || true"

attach:
	ssh -t claude-home

attach-codex:
	ssh -t codex-home tmux new-session -A -s codex-main

attach-agent:
	@case "$$AGENT" in agy|hermes|kimi|opencode) ;; *) echo "Usage: make attach-agent AGENT={agy|hermes|kimi|opencode}" >&2; exit 2;; esac
	ssh -t codex-home tmux new-session -A -s "$$AGENT-main"

attach-agy:
	@$(MAKE) --no-print-directory attach-agent AGENT=agy

attach-hermes:
	@$(MAKE) --no-print-directory attach-agent AGENT=hermes

attach-kimi:
	@$(MAKE) --no-print-directory attach-agent AGENT=kimi

attach-opencode:
	@$(MAKE) --no-print-directory attach-agent AGENT=opencode

connect-deepseek:
	@echo "In OpenCode: run /connect, choose DeepSeek, complete its key prompt, then run /models."
	@echo "Store a newly created DeepSeek key in 1Password before entering it on the node."
	@$(MAKE) --no-print-directory attach-opencode

remote-control: env
	@. ./.env && \
	ssh -t -o RemoteCommand=none "$$HOMELAB_SSH_USER@$$HOMELAB_TAILSCALE_IP" \
		'export PATH="$$HOME/.local/bin:$$PATH"; codex app-server daemon bootstrap --remote-control'

ollama-install: env
	@. ./.env && \
	ssh -t -o RemoteCommand=none "$$HOMELAB_SSH_USER@$$HOMELAB_TAILSCALE_IP" \
		"chmod +x ~/homelab/scripts/install-ollama.sh && ~/homelab/scripts/install-ollama.sh"

ollama-status: env
	@. ./.env && \
	ssh -o RemoteCommand=none "$$HOMELAB_SSH_USER@$$HOMELAB_TAILSCALE_IP" \
		'sudo systemctl status ollama.service --no-pager || true; echo; ollama list'

ollama-pull: env
	@test -n "$$MODEL" || { echo "Usage: make ollama-pull MODEL=<model>" >&2; exit 2; }
	@. ./.env; printf '%s\n' "$$MODEL" | ssh -o RemoteCommand=none "$$HOMELAB_SSH_USER@$$HOMELAB_TAILSCALE_IP" 'IFS= read -r model; case "$$model" in *[!A-Za-z0-9._:/-]*|"") echo "Invalid model name" >&2; exit 2;; esac; ollama pull "$$model"'

setup: env ssh-config bootstrap harden terminfo
	@echo ""
	@echo "Done. Run 'make attach', 'make attach-codex', or an agent-specific attach target to connect."
