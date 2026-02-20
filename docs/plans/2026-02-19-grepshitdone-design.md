# grepShitDone — Design Document
_2026-02-19_

## Problem

grepai and GSD (Get Shit Done) cannot work together out of the box. There are five specific
incompatibilities between them.

### Incompatibilities

**1. `Skill` tool blocked in all GSD subagents**
Every GSD subagent (`gsd-executor`, `gsd-planner`, `gsd-phase-researcher`, etc.) has a closed
`tools:` list. None include the `Skill` tool. grepai's SKILL.md description reads: "You MUST
invoke this skill BEFORE using WebSearch, Grep, or Glob." This invocation is impossible inside
any GSD workflow.

**2. Skill directory mismatch**
`gsd-executor` scans `.agents/skills/` for project skills. grepai places its skill at
`.claude/skills/grepai/SKILL.md`. GSD subagents never find or load it.

**3. No daemon lifecycle management**
grepai requires `grepai watch` to be running before `grepai search` works. GSD has no mechanism
to verify or start this daemon before spawning subagents.

**4. Hardcoded `grep` in GSD workflows**
GSD agent prompts issue `grep` via Bash for their own orchestration (e.g.
`grep -n "type=\"checkpoint" [plan-path]`). These GSD-internal calls cannot be routed through
grepai, yet grepai's SKILL.md says "NEVER use the built-in Grep tool."

**5. Scope conflict on web/library research**
grepai claims to replace "ALL" search tools including WebSearch. GSD's `gsd-phase-researcher`
and `gsd-planner` use WebFetch and `mcp__context7__*` for external library research — queries
where grepai has no role.

---

## Solution

A self-installing bridge called **grepShitDone**. Install once by cloning and running a script.
Every Claude Code session after that runs automatically. Nothing to think about.

### Distribution

```
git clone https://github.com/<org>/grepShitDone
cd grepShitDone
./install.sh
```

`install.sh` is idempotent — safe to re-run after `git pull` to pick up updates.

---

## Architecture

Three components work together:

```
[SessionStart hook]
    → starts grepai daemon (if installed, if not running)
    → writes .agents/skills/grepai/SKILL.md into CWD   ← GSD subagents load this
    → appends to .gitignore so the file isn't committed

[~/.claude/CLAUDE.md injection]
    → grepai rules for the main Claude orchestrator session
    → same rules as the adapter, applied at the top-level session

[adapter/SKILL.md]
    → the template written into every project
    → GSD-compatible: Bash-only, no Skill tool required
    → source of truth, updated on git pull + ./install.sh re-run
```

### Coverage

| Agent | How it gets grepai rules |
|---|---|
| Main orchestrator | `~/.claude/CLAUDE.md` (injected at install time) |
| `gsd-executor` | `.agents/skills/grepai/SKILL.md` (written by hook) |
| `gsd-planner` | `.agents/skills/grepai/SKILL.md` (written by hook) |
| `gsd-phase-researcher` | `.agents/skills/grepai/SKILL.md` (written by hook) |
| All other GSD subagents | `.agents/skills/grepai/SKILL.md` (written by hook) |

---

## Repository Structure

```
grepShitDone/
├── install.sh          ← idempotent installer
├── hook.sh             ← SessionStart hook (copied to ~/.claude/grepshitdone/)
├── adapter/
│   └── SKILL.md        ← GSD-compatible grepai adapter template
└── README.md
```

---

## Component Designs

### hook.sh

```sh
#!/bin/sh
# grepShitDone SessionStart hook
# Bridges grepai semantic search into GSD workflows.
# Exits silently if grepai is not installed.

command -v grepai >/dev/null 2>&1 || exit 0

# Start daemon if not responding
grepai status >/dev/null 2>&1 || grepai watch --daemon >/dev/null 2>&1 &

# Write GSD-compatible adapter into current project
mkdir -p .agents/skills/grepai
cp ~/.claude/grepshitdone/SKILL.md .agents/skills/grepai/SKILL.md

# Keep generated file out of version control
if [ -f .gitignore ] && ! grep -q "\.agents/skills/grepai" .gitignore; then
  printf '\n# grepShitDone (auto-generated)\n.agents/skills/grepai/\n' >> .gitignore
fi
```

### install.sh

Actions (all idempotent):
1. Copy `hook.sh` → `~/.claude/grepshitdone/hook.sh`
2. Copy `adapter/SKILL.md` → `~/.claude/grepshitdone/SKILL.md`
3. Register hook in `~/.claude/settings.json` under `hooks.SessionStart`
4. Inject grepai section into `~/.claude/CLAUDE.md` (guarded by marker comment)
5. Print confirmation

### adapter/SKILL.md — Routing Rules

The adapter encodes five disambiguation rules that resolve all five incompatibilities:

| Query type | Tool to use | Rationale |
|---|---|---|
| Semantic / intent-based | `grepai search "..." --json --compact` via Bash | grepai's primary use case |
| Exact text, variable names, imports | `Grep` built-in | grepai's own docs recommend this |
| GSD-internal orchestration greps | Bash `grep` directly | Exempt — GSD infra, not code search |
| File path patterns | `Glob` built-in | Unchanged |
| External library / web research | `WebFetch` / `mcp__context7__*` | Out of scope for grepai |

Fallback: if `grepai search` exits non-zero, fall back to `Grep` silently.

No `Skill` tool invocation. Purely instructional — GSD subagents read it as a text file
via their existing `project_context` skill-loading logic.

---

## Behaviour Matrix

| grepai installed? | grepai daemon running? | Result |
|---|---|---|
| No | — | Hook exits in ~1ms, zero overhead |
| Yes | Yes | Adapter written, done |
| Yes | No | Daemon started in background, adapter written |

---

## Update Flow

```
cd grepShitDone
git pull
./install.sh        ← idempotent, updates hook + adapter in place
```

Next session, the updated adapter is written to every project automatically.
