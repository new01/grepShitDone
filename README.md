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
git clone https://github.com/cyne-wulf/grepShitDone
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

1. Exits silently if `grepai` is not on your PATH — zero overhead, nothing happens
2. Starts the `grepai watch` daemon if it isn't already running
3. Writes a GSD-compatible adapter to `.agents/skills/grepai/SKILL.md` in your project
4. Adds `.agents/skills/grepai/` to `.gitignore` so the generated file isn't committed

GSD subagents (`gsd-executor`, `gsd-planner`, `gsd-phase-researcher`, etc.) automatically
scan `.agents/skills/` on boot and load any `SKILL.md` files they find. The adapter teaches
them when to use `grepai search` instead of `Grep`. The main Claude orchestrator gets the
same rules via an injected section in `~/.claude/CLAUDE.md`.

## The incompatibilities this solves

| Problem | Solution |
|---|---|
| GSD subagents can't invoke the `Skill` tool | Adapter is plain text — no invocation needed |
| GSD looks in `.agents/skills/`, not `.claude/skills/` | Hook writes adapter to the right place each session |
| grepai daemon not running | Hook starts it automatically |
| grepai says "never use Grep"; GSD uses `grep` internally | Adapter exempts GSD orchestration calls from the rule |
| grepai claims to replace WebSearch | Adapter scopes grepai to local code only |

## What gets installed

```
~/.claude/
└── grepshitdone/
    ├── hook.sh       ← the SessionStart hook (registered in settings.json)
    └── SKILL.md      ← the adapter template (copied into projects each session)
```

Plus a `grepai` section appended to `~/.claude/CLAUDE.md`.

Nothing else on your system is modified.
