#!/usr/bin/env bash
# Installs Ollama's server only. Models are intentionally never downloaded by
# bootstrap: choosing a model has significant disk/RAM implications.

set -euo pipefail

if command -v ollama >/dev/null 2>&1; then
  echo "==> Ollama already installed: $(ollama --version 2>&1 || true)"
else
  echo "==> Installing Ollama server (no models will be downloaded)"
  curl -fsSL https://ollama.com/install.sh | sh
fi

echo "==> Ollama status:"
if systemctl list-unit-files ollama.service --no-legend 2>/dev/null | grep -q '^ollama.service'; then
  sudo systemctl enable --now ollama.service
  sudo systemctl status ollama.service --no-pager || true
else
  echo "Ollama installed, but no systemd service was detected. Start it with: ollama serve"
fi

echo "No model was downloaded. After checking available RAM, run: make ollama-pull MODEL=<model>"
