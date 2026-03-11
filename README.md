# grepShitDone

Bridges [grepai](https://github.com/yoanbernabeu/grepai) semantic search into
[GSD (Get Shit Done)](https://github.com/glittercowboy/get-shit-done) workflows.

Install once. Never think about it again.

---

## Architecture Overview

```mermaid
graph TB
    subgraph "Claude Code Session"
        CC[Claude Orchestrator]
        subgraph "GSD Subagents"
            GE[gsd-executor]
            GP[gsd-planner]
            GPR[gsd-phase-researcher]
        end
    end

    subgraph "grepShitDone Bridge"
        HOOK["hook.sh\n(SessionStart)"]
        SKILL["SKILL.md\nAdapter"]
        CLAUDEMD["~/.claude/CLAUDE.md\nInjected rules"]
    end

    subgraph "Search Layer"
        GREPAI["grepai daemon\n(semantic index)"]
        GREP["Built-in Grep\n(exact match)"]
        GLOB["Built-in Glob\n(file patterns)"]
    end

    HOOK -->|"writes each session"| SKILL
    SKILL -->|".agents/skills/grepai/"| GE
    SKILL -->|".agents/skills/grepai/"| GP
    SKILL -->|".agents/skills/grepai/"| GPR
    CLAUDEMD -->|"global rules"| CC

    HOOK -->|"starts if not running"| GREPAI

    GE -->|"intent search"| GREPAI
    GP -->|"intent search"| GREPAI
    GPR -->|"intent search"| GREPAI
    CC -->|"intent search"| GREPAI

    GE -->|"exact match"| GREP
    CC -->|"exact match"| GREP
    CC -->|"file patterns"| GLOB
```

---

## How It Works

A `SessionStart` hook fires at the start of every Claude Code session:

```mermaid
flowchart TD
    A([Session Start]) --> B{grepai on PATH?}
    B -- No --> Z([Exit silently — zero overhead])
    B -- Yes --> C{grepai watch\nalready running?}
    C -- No --> D[Start grepai watch daemon\nnohup in background]
    C -- Yes --> E
    D --> E{SKILL.md exists\nin ~/.claude/grepshitdone/?}
    E -- Yes --> F["Copy SKILL.md →\n.agents/skills/grepai/SKILL.md"]
    E -- No --> G
    F --> G{.gitignore\npresent?}
    G -- Yes --> H{.agents/skills/grepai/\nalready in .gitignore?}
    H -- No --> I["Append .agents/skills/grepai/\nto .gitignore"]
    H -- Yes --> J
    G -- No --> J
    I --> J([Exit 0])
```

GSD subagents (`gsd-executor`, `gsd-planner`, `gsd-phase-researcher`, etc.) automatically
scan `.agents/skills/` on boot and load any `SKILL.md` files they find. The adapter teaches
them when to use `grepai search` instead of `Grep`. The main Claude orchestrator gets the
same rules via an injected section in `~/.claude/CLAUDE.md`.

---

## Search Routing

```mermaid
flowchart TD
    Q["Search needed"] --> A{What kind\nof search?}

    A -->|"Intent / meaning\ne.g. 'auth flow'"| B[grepai search]
    A -->|"Exact text\nfunction name / import / literal"| C[Built-in Grep]
    A -->|"File path pattern\n*.go / src/**/*.ts"| D[Built-in Glob]
    A -->|"External docs\nor web research"| E[WebFetch / context7]

    B --> F{Result?}
    F -->|"Hits found"| G[Extract file paths → Read]
    F -->|"Zero results"| H[Rephrase once → retry]
    H --> I{Still empty?}
    I -->|"Yes"| C
    I -->|"No"| G

    G --> J{Need call\nrelationships?}
    J -->|"Yes"| K["grepai trace callers/callees/graph"]
    J -->|"No"| L([Done])
    K --> L

    style B fill:#4a90d9,color:#fff
    style C fill:#7b7b7b,color:#fff
    style D fill:#7b7b7b,color:#fff
    style E fill:#7b7b7b,color:#fff
```

> **GSD orchestration exception:** Internal GSD calls (checkpoint parsing, STATE.md queries,
> plan frontmatter scanning) use `bash grep` directly and are exempt from the routing rules above.
> These are infrastructure calls, not code searches.

---

## Installation Flow

```mermaid
flowchart TD
    A([Run ./install.sh]) --> B["Create ~/.claude/grepshitdone/"]
    B --> C["Copy hook.sh → ~/.claude/grepshitdone/hook.sh\nchmod +x"]
    C --> D["Copy adapter/SKILL.md → ~/.claude/grepshitdone/SKILL.md"]
    D --> E{~/.claude/settings.json\nexists?}

    E -- No --> F["Create settings.json\nwith SessionStart hook entry"]
    E -- Yes --> G{Hook already\nregistered?}
    G -- Yes --> H
    G -- No --> I["jq-append hook entry\nto SessionStart array"]
    I --> H

    F --> H{~/.claude/CLAUDE.md\nhas grepshitdone:start?}
    H -- Yes --> J["Skip — already up to date"]
    H -- No --> K["Append grepai rules block\nbetween grepshitdone:start/end markers"]
    J --> L
    K --> L([Done — start a new session])

    style A fill:#2d8a4e,color:#fff
    style L fill:#2d8a4e,color:#fff
```

---

## What Gets Installed

```
~/.claude/
└── grepshitdone/
    ├── hook.sh       ← SessionStart hook (registered in settings.json)
    └── SKILL.md      ← Adapter template (copied into projects each session)

~/.claude/settings.json
└── hooks.SessionStart[]  ← hook.sh entry appended

~/.claude/CLAUDE.md
└── <!-- grepshitdone:start/end -->  ← grepai rules block appended
```

Per-project (written each session, never committed):

```
<project>/
└── .agents/
    └── skills/
        └── grepai/
            └── SKILL.md   ← auto-generated, in .gitignore
```

Nothing else on your system is modified.

---

## The Incompatibilities This Solves

| Problem | Solution |
|---|---|
| GSD subagents can't invoke the `Skill` tool | Adapter is plain text — no invocation needed |
| GSD looks in `.agents/skills/`, not `.claude/skills/` | Hook writes adapter to the right place each session |
| grepai daemon not running | Hook starts it automatically |
| grepai says "never use Grep"; GSD uses `grep` internally | Adapter exempts GSD orchestration calls from the rule |
| grepai claims to replace WebSearch | Adapter scopes grepai to local code only |

---

## Prerequisites

- [grepai](https://github.com/yoanbernabeu/grepai) installed and on your PATH
- [GSD](https://github.com/glittercowboy/get-shit-done) installed in Claude Code
- `jq` installed (`brew install jq` on macOS)

---

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
