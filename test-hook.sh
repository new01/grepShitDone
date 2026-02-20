#!/bin/sh
# Smoke tests for hook.sh
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

# --- Test 1: exits 0 silently when grepai not on PATH ---
OLD_PATH="$PATH"
export PATH="/nonexistent"
/bin/sh "$SCRIPT_DIR/hook.sh" >/dev/null 2>&1
check "exits 0 when grepai not installed" "[ $? -eq 0 ]"
export PATH="$OLD_PATH"

# --- Setup: mock grepai binary and temp home ---
MOCK_BIN="$(mktemp -d)"
cat > "$MOCK_BIN/grepai" << 'GREPAI'
#!/bin/sh
exit 0
GREPAI
chmod +x "$MOCK_BIN/grepai"

WORK_DIR="$(mktemp -d)"
FAKE_HOME="$(mktemp -d)"
mkdir -p "$FAKE_HOME/.claude/grepshitdone"
cp "$SCRIPT_DIR/adapter/SKILL.md" "$FAKE_HOME/.claude/grepshitdone/SKILL.md"

OLD_PATH="$PATH"
OLD_HOME="$HOME"
export PATH="$MOCK_BIN:$PATH"
export HOME="$FAKE_HOME"

/bin/sh "$SCRIPT_DIR/hook.sh" >/dev/null 2>&1
RET=$?

# --- Test 2: exits 0 when grepai is on PATH ---
# (re-run in workdir)
cd "$WORK_DIR"
/bin/sh "$SCRIPT_DIR/hook.sh" >/dev/null 2>&1
check "exits 0 when grepai is installed" "[ $? -eq 0 ]"

# --- Test 3: creates .agents/skills/grepai/ directory ---
check "creates .agents/skills/grepai/" "[ -d '$WORK_DIR/.agents/skills/grepai' ]"

# --- Test 4: writes SKILL.md into the project ---
check "writes SKILL.md" "[ -f '$WORK_DIR/.agents/skills/grepai/SKILL.md' ]"

# --- Test 5: idempotent .gitignore update ---
touch "$WORK_DIR/.gitignore"
/bin/sh "$SCRIPT_DIR/hook.sh" >/dev/null 2>&1
/bin/sh "$SCRIPT_DIR/hook.sh" >/dev/null 2>&1
/bin/sh "$SCRIPT_DIR/hook.sh" >/dev/null 2>&1
COUNT=$(grep -c "grepai" "$WORK_DIR/.gitignore" 2>/dev/null || echo 0)
check "gitignore entry written exactly once across multiple runs" "[ '$COUNT' -eq 1 ]"

# --- Cleanup ---
export PATH="$OLD_PATH"
export HOME="$OLD_HOME"
rm -rf "$MOCK_BIN" "$WORK_DIR" "$FAKE_HOME"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
