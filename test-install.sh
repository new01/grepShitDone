#!/bin/sh
PASS=0
FAIL=0
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

check() {
  if eval "$2"; then
    echo "PASS: $1"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $1"
    FAIL=$((FAIL + 1))
  fi
}

# Isolated fake home — never touch real ~/.claude
FAKE_HOME="$(mktemp -d)" || { echo "mktemp failed"; exit 1; }
trap 'rm -rf "$FAKE_HOME"' EXIT INT TERM
mkdir -p "$FAKE_HOME/.claude"

# Pre-populate settings.json mirroring real user state
cat > "$FAKE_HOME/.claude/settings.json" << 'EOF'
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "node \"/Users/adevine/.claude/hooks/gsd-check-update.js\""
          }
        ]
      }
    ]
  }
}
EOF

# Run install against fake home
HOME="$FAKE_HOME" sh "$SCRIPT_DIR/install.sh"

# Test 1: hook.sh copied
check "hook.sh copied to ~/.claude/grepshitdone/" \
  "[ -f '$FAKE_HOME/.claude/grepshitdone/hook.sh' ]"

# Test 2: hook.sh is executable
check "hook.sh is executable" \
  "[ -x '$FAKE_HOME/.claude/grepshitdone/hook.sh' ]"

# Test 3: SKILL.md copied
check "SKILL.md copied to ~/.claude/grepshitdone/" \
  "[ -f '$FAKE_HOME/.claude/grepshitdone/SKILL.md' ]"

# Test 4: hook registered in settings.json
check "hook registered in settings.json" \
  "jq -e '[.hooks.SessionStart[].hooks[] | select(.command | contains(\"grepshitdone\"))] | length > 0' '$FAKE_HOME/.claude/settings.json' >/dev/null 2>&1"

# Test 5: CLAUDE.md grepai section written
check "CLAUDE.md grepai section written" \
  "grep -q 'grepshitdone:start' '$FAKE_HOME/.claude/CLAUDE.md'"

# Test 6: idempotency — run install twice more, hook still registered exactly once
HOME="$FAKE_HOME" sh "$SCRIPT_DIR/install.sh" >/dev/null 2>&1
HOME="$FAKE_HOME" sh "$SCRIPT_DIR/install.sh" >/dev/null 2>&1
HOOK_COUNT=$(jq '[.hooks.SessionStart[].hooks[] | select(.command | contains("grepshitdone"))] | length' "$FAKE_HOME/.claude/settings.json")
check "hook registered exactly once after three runs" "[ '$HOOK_COUNT' -eq 1 ]"

# Test 7: idempotency — CLAUDE.md section appears exactly once
SECTION_COUNT=$(grep -c "grepshitdone:start" "$FAKE_HOME/.claude/CLAUDE.md" 2>/dev/null || echo 0)
check "CLAUDE.md section written exactly once after three runs" "[ '$SECTION_COUNT' -eq 1 ]"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
