#!/bin/sh
# grepShitDone — SessionStart hook
# Bridges grepai semantic search into GSD (Get Shit Done) workflows.
# Runs at the start of every Claude Code session.
# Silent on success. Always exits 0 — never breaks Claude Code startup.

# Nothing to do if grepai isn't installed
command -v grepai >/dev/null 2>&1 || exit 0

# Start grepai watch daemon if not already running
if ! pgrep -f "grepai watch" >/dev/null 2>&1; then
  nohup grepai watch >/dev/null 2>&1 &
fi

# Copy the GSD-compatible adapter into the current project.
# GSD subagents automatically scan .agents/skills/ on boot — no invocation needed.
SKILL_SRC="$HOME/.claude/grepshitdone/SKILL.md"
SKILL_DST=".agents/skills/grepai/SKILL.md"

if [ -f "$SKILL_SRC" ]; then
  mkdir -p ".agents/skills/grepai"
  cp "$SKILL_SRC" "$SKILL_DST"
fi

# Add .agents/skills/grepai/ to .gitignore (idempotent — only adds if absent)
if [ -f ".gitignore" ] && ! grep -qF ".agents/skills/grepai" .gitignore; then
  printf '\n# grepShitDone (auto-generated, do not commit)\n.agents/skills/grepai/\n' >> .gitignore
fi

exit 0
