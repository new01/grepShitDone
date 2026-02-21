#!/bin/sh
# grepShitDone installer
# Run once after: git clone https://github.com/cyne-wulf/grepShitDone && cd grepShitDone
# Safe to re-run after git pull — all operations are idempotent.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEST_DIR="$HOME/.claude/grepshitdone"
SETTINGS="$HOME/.claude/settings.json"
CLAUDE_MD="$HOME/.claude/CLAUDE.md"

echo "Installing grepShitDone..."

# 1. Copy hook and adapter to ~/.claude/grepshitdone/
mkdir -p "$DEST_DIR"
cp "$SCRIPT_DIR/hook.sh" "$DEST_DIR/hook.sh"
chmod +x "$DEST_DIR/hook.sh"
cp "$SCRIPT_DIR/adapter/SKILL.md" "$DEST_DIR/SKILL.md"
echo "  + Copied hook and adapter to $DEST_DIR"

# 2. Register hook in ~/.claude/settings.json (idempotent)
HOOK_CMD="$DEST_DIR/hook.sh"

if [ ! -f "$SETTINGS" ]; then
  # No settings.json yet — create one with just our hook
  printf '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"%s"}]}]}}\n' \
    "$HOOK_CMD" | jq . > "$SETTINGS"
else
  # Check if our hook is already registered
  # || echo 0: intentional set -e escape — tolerate corrupt JSON rather than aborting install
  ALREADY=$(jq --arg cmd "$HOOK_CMD" \
    '[.hooks.SessionStart[]?.hooks[]? | select(.command == $cmd)] | length' \
    "$SETTINGS" 2>/dev/null || echo 0)

  if [ "$ALREADY" -eq 0 ]; then
    jq --arg cmd "$HOOK_CMD" \
      '.hooks.SessionStart //= [] | .hooks.SessionStart += [{"hooks":[{"type":"command","command":$cmd}]}]' \
      "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
  fi
fi
echo "  + Hook registered in $SETTINGS"

# 3. Inject grepai section into ~/.claude/CLAUDE.md (idempotent)
if [ -f "$CLAUDE_MD" ] && grep -q "grepshitdone:start" "$CLAUDE_MD" 2>/dev/null; then
  echo "  + CLAUDE.md already up to date"
else
  cat >> "$CLAUDE_MD" << 'CLAUDEMD'

<!-- grepshitdone:start -->
## grepai Semantic Search

grepai is available as a background daemon. Use it for intent-based code search.

**Use `grepai search` (via Bash) for:**
- Searching by intent: "authentication flow", "error handling", "database connection"
- Exploring unfamiliar code or finding implementations by meaning

**Use built-in `Grep` for:**
- Exact text: function names, imports, specific string literals
- GSD orchestration calls (checkpoint parsing, STATE.md queries) — these are exempt

**Use `WebFetch` / `mcp__context7__*` for:**
- External library docs and web research (grepai only searches local code)

```bash
# JSON output fields: file (path), line (number), score (relevance), snippet (code preview)
grepai search "user authentication flow" --json --compact
grepai search "error handling middleware" --json --compact
grepai trace callers "FunctionName" --json

# Fallback: if grepai exits non-zero for any reason, use Grep silently
```
<!-- grepshitdone:end -->
CLAUDEMD
  echo "  + grepai section injected into $CLAUDE_MD"
fi

echo ""
echo "Done. Start a new Claude Code session to activate."
