#!/usr/bin/env bash
# restart-claude.sh - Restart (resume) this project's Claude Code session,
# keeping its conversation history and memory.
#
# Exit the running session first (/exit or Ctrl+D), then run this script from
# the same terminal.
#
# Usage: ./restart-claude.sh [extra claude args...]   e.g. ./restart-claude.sh --model opus
#        SESSION_ID=<uuid> ./restart-claude.sh        resume a different session
set -euo pipefail

SESSION_ID="${SESSION_ID:-50bfd7a7-85f0-47b5-92e6-a6b882115c9e}"

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_HOME="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# Claude Code names each project store after its path, with every
# non-alphanumeric character replaced by "-".
encode_path() { printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g'; }

STORE="$CLAUDE_HOME/projects/$(encode_path "$PROJECT_DIR")"

if ! command -v claude >/dev/null 2>&1; then
  echo "error: 'claude' CLI not found on PATH" >&2
  exit 1
fi

cd "$PROJECT_DIR"

if [[ -f "$STORE/$SESSION_ID.jsonl" ]]; then
  exec claude --resume "$SESSION_ID" "$@"
else
  echo "warning: transcript $SESSION_ID.jsonl not found in $STORE;" \
       "continuing the most recent session instead" >&2
  exec claude --continue "$@"
fi
