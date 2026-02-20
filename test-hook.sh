#!/bin/sh
# Smoke tests for hook.sh
PASS=0
FAIL=0
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Cleanup trap — uses :- defaults so it is safe even if variables are not yet set
# when the trap fires (e.g. early exit from an error before setup completes).
trap 'rm -rf "${MOCK_BIN:-}" "${WORK_DIR:-}" "${FAKE_HOME:-}" "${FRESH_DIR:-}"' EXIT INT TERM

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
RET=$?
check "exits 0 when grepai not installed" "[ $RET -eq 0 ]"
export PATH="$OLD_PATH"

# --- Setup: mock grepai binary and temp home ---
MOCK_BIN="$(mktemp -d)" || { echo "mktemp failed"; exit 1; }
cat > "$MOCK_BIN/grepai" << 'GREPAI'
#!/bin/sh
exit 0
GREPAI
chmod +x "$MOCK_BIN/grepai"

WORK_DIR="$(mktemp -d)" || { echo "mktemp failed"; exit 1; }
FAKE_HOME="$(mktemp -d)" || { echo "mktemp failed"; exit 1; }
mkdir -p "$FAKE_HOME/.claude/grepshitdone"
cp "$SCRIPT_DIR/adapter/SKILL.md" "$FAKE_HOME/.claude/grepshitdone/SKILL.md"

OLD_PATH="$PATH"
OLD_HOME="$HOME"
export PATH="$MOCK_BIN:$PATH"
export HOME="$FAKE_HOME"

# --- Test 2: exits 0 when grepai is on PATH ---
cd "$WORK_DIR"
/bin/sh "$SCRIPT_DIR/hook.sh" >/dev/null 2>&1
RET=$?
check "exits 0 when grepai is installed" "[ $RET -eq 0 ]"

# --- Tests 3 & 4: run hook in a fresh isolated directory ---
# Using a dedicated temp dir makes these tests independent of Test 2's side effects.
FRESH_DIR="$(mktemp -d)" || { echo "mktemp failed"; exit 1; }
cd "$FRESH_DIR"
/bin/sh "$SCRIPT_DIR/hook.sh" >/dev/null 2>&1

# --- Test 3: creates .agents/skills/grepai/ directory ---
check "creates .agents/skills/grepai/" "[ -d '$FRESH_DIR/.agents/skills/grepai' ]"

# --- Test 4: writes SKILL.md into the project ---
check "writes SKILL.md" "[ -f '$FRESH_DIR/.agents/skills/grepai/SKILL.md' ]"

# --- Note on daemon-already-running branch ---
# The branch in hook.sh where pgrep detects an existing "grepai watch" process
# and skips starting a new one is not tested here because renaming an arbitrary
# process to match a pgrep pattern is not portable across platforms.

# --- Test 5: idempotent .gitignore update ---
# .agents/ is already populated from prior hook runs; that is fine because this
# test only asserts .gitignore idempotency, not directory creation.
touch "$WORK_DIR/.gitignore"
cd "$WORK_DIR"
/bin/sh "$SCRIPT_DIR/hook.sh" >/dev/null 2>&1
/bin/sh "$SCRIPT_DIR/hook.sh" >/dev/null 2>&1
/bin/sh "$SCRIPT_DIR/hook.sh" >/dev/null 2>&1
COUNT=$(grep -c "grepai" "$WORK_DIR/.gitignore" 2>/dev/null || echo 0)
check "gitignore entry written exactly once across multiple runs" "[ '$COUNT' -eq 1 ]"

# --- Cleanup ---
export PATH="$OLD_PATH"
export HOME="$OLD_HOME"
# Temp dirs are removed by the EXIT trap above.

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
