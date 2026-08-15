#!/usr/bin/env bash
# Run this ON YOUR CLIENT (laptop), not the remote node. Pushes your
# current terminal's terminfo entry to a remote host so tmux/vim/etc.
# don't refuse to start with "missing or unsuitable terminal: $TERM".
#
# Why this is needed: newer/less common terminal emulators (Ghostty,
# WezTerm, kitty) set a $TERM value that minimal Linux installs don't ship
# a terminfo entry for. iTerm2/Terminal.app use xterm-256color, which is
# universally present, so this only bites you with newer terminals.
#
# Usage:
#   ./scripts/install-client-terminfo.sh claude-home
#   ./scripts/install-client-terminfo.sh youruser@100.x.x.x

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <ssh-host-or-alias>" >&2
  exit 1
fi

TARGET="$1"

if ! infocmp "$TERM" >/dev/null 2>&1; then
  echo "No local terminfo entry for \$TERM=$TERM -- nothing to push." >&2
  exit 1
fi

echo "Checking if $TARGET already has a terminfo entry for '$TERM'..."
if ssh -o RemoteCommand=none "$TARGET" "infocmp '$TERM'" >/dev/null 2>&1; then
  echo "Already present on $TARGET. Nothing to do."
  exit 0
fi

echo "Pushing terminfo entry for '$TERM' to $TARGET..."
infocmp -x "$TERM" | ssh -o RemoteCommand=none "$TARGET" -- tic -x -o '~/.terminfo' /dev/stdin

echo "Done. tmux/vim on $TARGET should now recognize \$TERM=$TERM."
