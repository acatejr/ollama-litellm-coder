#!/usr/bin/env bash
# rsc.sh - Resume the Claude Code session for this project, with its history
# and memory.
#
# The session was started when this folder was named "s-2vcpu-8gb". Claude Code
# stores transcripts per folder path, so on first run this copies the transcript
# and memory into the store for the current folder path, then resumes.
#
# Usage: ./rsc.sh [extra claude args...]     e.g. ./rsc.sh --model opus
set -euo pipefail

SESSION_ID="e204dc47-137b-499d-a139-a5684d13e0ba"
OLD_PROJECT_PATH="/home/acatejr/workspace/github.com/acatejr/s-2vcpu-8gb"

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_HOME="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# Claude Code names each project store after its path, with every
# non-alphanumeric character replaced by "-".
encode_path() { printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g'; }

OLD_STORE="$CLAUDE_HOME/projects/$(encode_path "$OLD_PROJECT_PATH")"
NEW_STORE="$CLAUDE_HOME/projects/$(encode_path "$PROJECT_DIR")"

if ! command -v claude >/dev/null 2>&1; then
  echo "error: 'claude' CLI not found on PATH" >&2
  exit 1
fi

mkdir -p "$NEW_STORE"

# Copy (never move) the transcript so the original stays as a backup.
if [[ ! -f "$NEW_STORE/$SESSION_ID.jsonl" ]]; then
  if [[ -f "$OLD_STORE/$SESSION_ID.jsonl" ]]; then
    cp -p "$OLD_STORE/$SESSION_ID.jsonl" "$NEW_STORE/"
    echo "Copied session transcript to $NEW_STORE"
  else
    echo "error: transcript $SESSION_ID.jsonl not found in $OLD_STORE or $NEW_STORE" >&2
    exit 1
  fi
fi

# Copy memory files that don't already exist in the new store.
if [[ -d "$OLD_STORE/memory" ]]; then
  mkdir -p "$NEW_STORE/memory"
  for f in "$OLD_STORE/memory/"*; do
    [[ -e "$f" ]] || continue
    [[ -e "$NEW_STORE/memory/$(basename "$f")" ]] || cp -rp "$f" "$NEW_STORE/memory/"
  done
fi

cd "$PROJECT_DIR"
exec claude --resume "$SESSION_ID" "$@"
