#!/usr/bin/env bash
# PreToolUse hook (Bash matcher): deterministically blocks production deploys
# unless a release manager has written the single-use approval token.
# Synced into app-source/.claude/hooks/ by sync-governance.sh.
set -uo pipefail

INPUT="$(cat)"
CMD="$(printf '%s' "$INPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))' 2>/dev/null)"

# Only production deploy commands are gated.
if printf '%s' "$CMD" | grep -qE '(deploy\.sh|docker compose)[^|;&]*\bprod\b'; then
  ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
  if [[ ! -f "$ROOT/deploy/.release-approval" ]]; then
    echo "deploy-gate: PRODUCTION DEPLOY BLOCKED — no release approval on file." >&2
    echo "A release manager must run: echo '<image-tag>' > deploy/.release-approval" >&2
    exit 2
  fi
fi
exit 0
