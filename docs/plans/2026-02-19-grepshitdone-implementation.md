# grepShitDone Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** A self-installing bridge that makes grepai semantic search work transparently inside all GSD workflows, installed once via `git clone` + `./install.sh`, never touched again.

**Architecture:** A `SessionStart` hook copies a GSD-compatible grepai adapter into every project on each session start. An `install.sh` registers that hook globally and injects grepai routing rules into `~/.claude/CLAUDE.md` for the main orchestrator. No existing tools (GSD or grepai) are modified.

**Tech Stack:** POSIX shell (`/bin/sh`), `jq` (JSON manipulation), standard Unix tools. No Node, no npm, no external dependencies beyond what's already on the system.

---

## Context: How GSD finds project skills

`gsd-executor` and all other GSD subagents have this in their agent definition:

```
**Project skills:** Check `.agents/skills/` directory if it exists:
1. List available skills (subdirectories)
2. Read `SKILL.md` for each skill
3. Follow skill rules relevant to your current task
```

So anything we write to `.agents/skills/grepai/SKILL.md` is automatically loaded by every GSD subagent — no patching of GSD required.

## Context: settings.json hook format

The `~/.claude/settings.json` `SessionStart` array looks like this:

```json
"SessionStart": [
  {
    "hooks": [
      {
        "type": "command",
        "command": "node \"/path/to/existing-hook.js\""
      }
    ]
  }
]
```

We append a new object to this array. Use `jq` to do it safely.

## Context: files we'll touch

- **Create:** `adapter/SKILL.md` — the GSD-compatible grepai adapter template
- **Create:** `hook.sh` — the SessionStart hook script
- **Create:** `install.sh` — the one-time installer
- **Create:** `README.md` — install instructions
- **Modify at install time (not in repo):** `~/.claude/settings.json`, `~/.claude/CLAUDE.md`

---

## Task 1: adapter/SKILL.md

This is the most important file. It gets copied into every project by the hook. GSD subagents
load it automatically. It must work with no `Skill` tool — purely instructional text read as a
file.

**Files:**
- Create: `adapter/SKILL.md`

**Step 1: Create the adapter directory and file**

```bash
mkdir -p adapter
```

Write `adapter/SKILL.md` with this exact content:

```markdown
---
name: grepai
description: Semantic code search. Replaces intent-based Grep usage. No skill invocation needed — rules below apply directly.
---

## Search Routing Rules

Apply these rules for every search operation:

### Use `grepai search` (via Bash) when:
- Searching by **intent or meaning**: "authentication flow", "error handling", "database connection"
- Exploring **unfamiliar code**: "how does the indexer work", "where is config loaded"
- Finding **implementations**: "user login logic", "token validation"
- Understanding **relationships**: use `grepai trace` (see below)

### Use built-in `Grep` when:
- Exact text match: specific function name, import statement, string literal
- File patterns: use `Glob` instead

### Use Bash `grep` directly (not grepai) when:
- GSD orchestration operations: checkpoint detection, plan frontmatter parsing, STATE.md
  queries. These are infrastructure calls, not code searches. Example:
  `grep -n "type=\"checkpoint" plan.md`

### Use `WebFetch` / `mcp__context7__*` for:
- External library docs, API references, web research. grepai only searches local code.

---

## How to call grepai

```bash
# Semantic search — always English, describe intent not implementation
grepai search "user authentication flow" --json --compact
grepai search "error handling middleware" --json --compact
grepai search "database connection pooling" --json --compact

# Limit results when you only need a few
grepai search "config loading" --json --compact -n 5

# Call graph: find everything that calls a function
grepai trace callers "FunctionName" --json

# Call graph: find everything a function calls
grepai trace callees "ProcessOrder" --json

# Full call graph around a symbol
grepai trace graph "ValidateToken" --depth 3 --json
```

**Fallback:** If `grepai search` exits non-zero (daemon not running, index unavailable),
fall back to built-in `Grep` silently. Do not surface the error to the user.

---

## Workflow

1. `grepai search` to find relevant code by intent
2. `grepai trace` to understand function relationships
3. `Read` to examine files from results
4. `Grep` only for exact string matches
```

**Step 2: Verify file was written**

```bash
cat adapter/SKILL.md
```

Expected: full file content printed, no errors.

**Step 3: Commit**

```bash
git add adapter/SKILL.md
git commit -m "feat: add GSD-compatible grepai adapter SKILL.md"
```

---

## Task 2: hook.sh

The `SessionStart` hook. Runs at the start of every Claude Code session. Must be fast,
silent on success, and safe to run in any directory including non-git, non-grepai projects.

**Files:**
- Create: `hook.sh`

**Step 1: Write a test script to verify hook behaviour**

Create `test-hook.sh`:

```bash
#!/bin/sh
# Smoke test for hook.sh
set -e

PASS=0
FAIL=0

check() {
  if eval "$2"; then
    echo "PASS: $1"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $1"
    FAIL=$((FAIL + 1))
  fi
}

# Test: hook exits 0 when grepai not on PATH
ORIG_PATH="$PATH"
export PATH="/nonexistent"
sh hook.sh
check "exits silently when grepai not installed" "[ $? -eq 0 ]"
export PATH="$ORIG_PATH"

# Test: hook writes adapter file when grepai is on PATH
# (mock grepai binary)
mkdir -p /tmp/grepshitdone-test/bin
cat > /tmp/grepshitdone-test/bin/grepai << 'EOF'
#!/bin/sh
# mock: status check exits 0, watch does nothing
exit 0
EOF
chmod +x /tmp/grepshitdone-test/bin/grepai

ORIG_PATH="$PATH"
export PATH="/tmp/grepshitdone-test/bin:$PATH"
TMPDIR=$(mktemp -d)
cd "$TMPDIR"
HOME_BAK="$HOME"
export HOME="$TMPDIR"
mkdir -p "$HOME/.claude/grepshitdone"
cp "$OLDPWD/adapter/SKILL.md" "$HOME/.claude/grepshitdone/SKILL.md"

sh "$OLDPWD/hook.sh"

check "creates .agents/skills/grepai/" "[ -d .agents/skills/grepai ]"
check "writes SKILL.md" "[ -f .agents/skills/grepai/SKILL.md ]"

# Test: second run is idempotent (no duplicate .gitignore lines)
touch .gitignore
sh "$OLDPWD/hook.sh"
sh "$OLDPWD/hook.sh"
COUNT=$(grep -c "grepai" .gitignore || echo 0)
check "gitignore entry added exactly once" "[ \"$COUNT\" -eq 1 ]"

export HOME="$HOME_BAK"
export PATH="$ORIG_PATH"
cd "$OLDPWD"
rm -rf "$TMPDIR" /tmp/grepshitdone-test

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
```

**Step 2: Run the test — expect failures (hook.sh doesn't exist yet)**

```bash
chmod +x test-hook.sh
sh test-hook.sh
```

Expected: FAIL messages (hook.sh missing).

**Step 3: Write hook.sh**

```bash
#!/bin/sh
# grepShitDone — SessionStart hook
# Bridges grepai semantic search into GSD workflows.
# Silent on success. Exits 0 always (never break Claude Code startup).

set -e

# Nothing to do if grepai isn't installed
command -v grepai >/dev/null 2>&1 || exit 0

# Start daemon if not already running
# pgrep -f is portable across macOS and Linux
if ! pgrep -f "grepai watch" >/dev/null 2>&1; then
  nohup grepai watch >/dev/null 2>&1 &
fi

# Write GSD-compatible adapter into the current project
SKILL_SRC="$HOME/.claude/grepshitdone/SKILL.md"
SKILL_DST=".agents/skills/grepai/SKILL.md"

if [ -f "$SKILL_SRC" ]; then
  mkdir -p ".agents/skills/grepai"
  cp "$SKILL_SRC" "$SKILL_DST"
fi

# Add .agents/skills/grepai/ to .gitignore (idempotent)
if [ -f ".gitignore" ] && ! grep -qF ".agents/skills/grepai" .gitignore; then
  printf '\n# grepShitDone (auto-generated, do not commit)\n.agents/skills/grepai/\n' >> .gitignore
fi

exit 0
```

**Step 4: Run the test — expect all passes**

```bash
sh test-hook.sh
```

Expected output:
```
PASS: exits silently when grepai not installed
PASS: creates .agents/skills/grepai/
PASS: writes SKILL.md
PASS: gitignore entry added exactly once

Results: 4 passed, 0 failed
```

**Step 5: Commit**

```bash
chmod +x hook.sh
git add hook.sh test-hook.sh
git commit -m "feat: add SessionStart hook with tests"
```

---

## Task 3: install.sh

Registers the hook globally and injects grepai rules into `~/.claude/CLAUDE.md` for the main
orchestrator. All operations are idempotent — safe to re-run after `git pull`.

**Files:**
- Create: `install.sh`

**Step 1: Write a test script for install.sh**

Create `test-install.sh`:

```bash
#!/bin/sh
set -e

PASS=0
FAIL=0

check() {
  if eval "$2"; then
    echo "PASS: $1"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $1"
    FAIL=$((FAIL + 1))
  fi
}

# Set up isolated test home
TMPDIR=$(mktemp -d)
export HOME="$TMPDIR"
mkdir -p "$HOME/.claude"

# Pre-populate settings.json with existing hook (mirrors real user state)
cat > "$HOME/.claude/settings.json" << 'EOF'
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

sh install.sh

check "hook.sh copied to ~/.claude/grepshitdone/" \
  "[ -f \"$HOME/.claude/grepshitdone/hook.sh\" ]"

check "SKILL.md copied to ~/.claude/grepshitdone/" \
  "[ -f \"$HOME/.claude/grepshitdone/SKILL.md\" ]"

check "hook registered in settings.json" \
  "jq -e '.hooks.SessionStart[] | .hooks[] | select(.command | contains(\"grepshitdone\"))' \"$HOME/.claude/settings.json\" >/dev/null 2>&1"

check "CLAUDE.md grepai section written" \
  "grep -q 'grepshitdone:start' \"$HOME/.claude/CLAUDE.md\""

# Idempotency: second run should not duplicate anything
sh install.sh
HOOK_COUNT=$(jq '[.hooks.SessionStart[] | .hooks[] | select(.command | contains("grepshitdone"))] | length' "$HOME/.claude/settings.json")
check "hook registered exactly once after two runs" "[ \"$HOOK_COUNT\" -eq 1 ]"
SECTION_COUNT=$(grep -c "grepshitdone:start" "$HOME/.claude/CLAUDE.md" || echo 0)
check "CLAUDE.md section written exactly once" "[ \"$SECTION_COUNT\" -eq 1 ]"

rm -rf "$TMPDIR"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
```

**Step 2: Run the test — expect failures**

```bash
chmod +x test-install.sh
sh test-install.sh
```

Expected: FAILs (install.sh doesn't exist yet).

**Step 3: Write install.sh**

```bash
#!/bin/sh
# grepShitDone installer
# Run once after cloning. Safe to re-run after git pull.
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
echo "  ✓ Copied hook and adapter to $DEST_DIR"

# 2. Register hook in ~/.claude/settings.json (idempotent)
HOOK_CMD="$DEST_DIR/hook.sh"

if [ ! -f "$SETTINGS" ]; then
  # settings.json doesn't exist — create minimal version
  printf '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"%s"}]}]}}\n' "$HOOK_CMD" \
    | jq . > "$SETTINGS"
else
  # Check if hook already registered
  ALREADY=$(jq --arg cmd "$HOOK_CMD" \
    '[.hooks.SessionStart[]?.hooks[]? | select(.command == $cmd)] | length' \
    "$SETTINGS" 2>/dev/null || echo 0)

  if [ "$ALREADY" -eq 0 ]; then
    # Ensure hooks.SessionStart exists, then append
    jq --arg cmd "$HOOK_CMD" \
      '.hooks.SessionStart //= [] | .hooks.SessionStart += [{"hooks":[{"type":"command","command":$cmd}]}]' \
      "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
  fi
fi
echo "  ✓ Hook registered in $SETTINGS"

# 3. Inject grepai section into ~/.claude/CLAUDE.md (idempotent)
if [ -f "$CLAUDE_MD" ] && grep -q "grepshitdone:start" "$CLAUDE_MD"; then
  echo "  ✓ CLAUDE.md already up to date"
else
  cat >> "$CLAUDE_MD" << 'CLAUDEMD'

<!-- grepshitdone:start -->
## grepai Semantic Search

grepai is running as a background daemon. Use it for intent-based code search.

**Use `grepai search` (via Bash) for:**
- Searching by intent: "authentication flow", "error handling", "database connection"
- Exploring unfamiliar code, finding implementations by meaning

**Use built-in `Grep` for:**
- Exact text: function names, imports, specific string literals
- GSD orchestration calls (checkpoint parsing, STATE.md queries) — these are exempt

**Use `WebFetch`/`mcp__context7__*` for:**
- External library docs and web research (out of grepai scope)

```bash
# Semantic search
grepai search "user authentication flow" --json --compact
grepai search "error handling middleware" --json --compact

# Call graph
grepai trace callers "FunctionName" --json

# Fallback: if grepai exits non-zero, use Grep silently
```
<!-- grepshitdone:end -->
CLAUDEMD
  echo "  ✓ grepai section injected into $CLAUDE_MD"
fi

echo ""
echo "Done. grepShitDone is installed."
echo "Start a new Claude Code session to activate."
```

**Step 4: Run the tests — expect all passes**

```bash
sh test-install.sh
```

Expected output:
```
PASS: hook.sh copied to ~/.claude/grepshitdone/
PASS: SKILL.md copied to ~/.claude/grepshitdone/
PASS: hook registered in settings.json
PASS: CLAUDE.md grepai section written
PASS: hook registered exactly once after two runs
PASS: CLAUDE.md section written exactly once

Results: 6 passed, 0 failed
```

**Step 5: Commit**

```bash
chmod +x install.sh
git add install.sh test-install.sh
git commit -m "feat: add idempotent install.sh with tests"
```

---

## Task 4: README.md

**Files:**
- Create: `README.md`

**Step 1: Write README.md**

```markdown
# grepShitDone

Bridges [grepai](https://github.com/yoanbernabeu/grepai) semantic search into
[GSD (Get Shit Done)](https://github.com/glittercowboy/get-shit-done) workflows.

Install once. Never think about it again.

## Prerequisites

- [grepai](https://github.com/yoanbernabeu/grepai) installed and on your PATH
- [GSD](https://github.com/glittercowboy/get-shit-done) installed in Claude Code
- `jq` installed (`brew install jq` on macOS)

## Install

```bash
git clone https://github.com/<org>/grepShitDone
cd grepShitDone
./install.sh
```

Start a new Claude Code session. Done.

## Update

```bash
cd grepShitDone
git pull
./install.sh
```

The next session picks up the updated adapter automatically.

## How it works

A `SessionStart` hook fires at the start of every Claude Code session. It:

1. Exits silently if `grepai` is not on your PATH (zero overhead)
2. Starts the `grepai watch` daemon if it isn't already running
3. Writes a GSD-compatible adapter to `.agents/skills/grepai/SKILL.md` in your project
4. Adds `.agents/skills/grepai/` to `.gitignore` so the generated file isn't committed

GSD subagents (`gsd-executor`, `gsd-planner`, etc.) automatically scan `.agents/skills/`
on startup and load the adapter. The main Claude orchestrator gets the same rules via
`~/.claude/CLAUDE.md`.

## The incompatibilities this solves

| Problem | Solution |
|---|---|
| GSD subagents can't invoke the `Skill` tool | Adapter is a plain text file, no invocation needed |
| GSD looks in `.agents/skills/`, not `.claude/skills/` | Hook writes adapter to the right place |
| grepai daemon not running | Hook starts it automatically |
| grepai says "never use Grep"; GSD uses grep internally | Adapter carves out an exemption for GSD orchestration |
| grepai claims to replace WebSearch | Adapter scopes grepai to local code only |
```

**Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add README with install instructions and explanation"
```

---

## Task 5: End-to-end smoke test

Verify the full install works against your real `~/.claude` directory.

**Step 1: Run install.sh against real home**

```bash
sh install.sh
```

Expected output:
```
Installing grepShitDone...
  ✓ Copied hook and adapter to /Users/<you>/.claude/grepshitdone
  ✓ Hook registered in /Users/<you>/.claude/settings.json
  ✓ grepai section injected into /Users/<you>/.claude/CLAUDE.md

Done. grepShitDone is installed.
Start a new Claude Code session to activate.
```

**Step 2: Verify settings.json has the hook**

```bash
jq '.hooks.SessionStart' ~/.claude/settings.json
```

Expected: array containing an entry with `"command"` pointing to `~/.claude/grepshitdone/hook.sh`.

**Step 3: Verify CLAUDE.md has the grepai section**

```bash
grep -A 5 "grepshitdone:start" ~/.claude/CLAUDE.md
```

Expected: grepai routing rules section.

**Step 4: Run install.sh again — verify idempotency**

```bash
sh install.sh
jq '[.hooks.SessionStart[] | .hooks[] | select(.command | contains("grepshitdone"))] | length' ~/.claude/settings.json
```

Expected: `1` (not 2).

**Step 5: Final commit**

```bash
git add .
git status  # should be clean; nothing new to add
```

If clean, you're done. If anything is untracked, review and add.

```bash
git log --oneline
```

Expected: 5 commits.

---

## Run all tests at once

```bash
sh test-hook.sh && sh test-install.sh
```
