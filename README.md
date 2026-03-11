# grepShitDone

> Bridges [grepai](https://github.com/yoanbernabeu/grepai) semantic search into [GSD (Get Shit Done)](https://github.com/glittercowboy/get-shit-done) workflows.

Install once. Never think about it again.

---

## What it does

GSD agents find relevant code using `Grep`, `Glob`, and `Read`. On an unfamiliar codebase, this means reading a lot of files that turn out to be irrelevant. Token costs accumulate — especially on the first pass through a new domain.

**grepShitDone installs a skill adapter that teaches GSD agents to reach for `grepai search` first.** Semantic search returns targeted chunks from across the entire codebase in one query. Fewer files read, less context consumed, same (or better) result.

---

## Performance

Two benchmark approaches, both on the same production codebase: **104 files, 768 indexed chunks, ~45,000 lines of JavaScript, Python, and shell.**

---

### Study 1 — Instrumented GSD sessions (real tool calls)

The gold standard comparison. Three research tasks run twice each: once with grepShitDone installed, once without. Token counts pulled directly from the Claude API response (`cache_creation_input_tokens` + `cache_read_input_tokens`).

| Task | Cache state | Without grepShitDone | With grepShitDone | Δ tokens | Δ cost |
|:-----|:------------|---------------------:|------------------:|---------:|-------:|
| Add retry logic to Discord delivery | Cold (first run) | 348,221 | 249,562 | **−98,659** | **−$0.058** |
| API overload fallback in humanizer | Warm (cached) | 33,110 | 33,509 | +399 | −$0.030 |
| Add dry-run mode to morning brief | Warm (cached) | 50,308 | 50,346 | +38 | +$0.001 |

**Cold run: 28% token reduction, $0.058 saved per task.**
**Warm cache: effectively zero difference** — GSD's prompt caching already eliminates redundant reads.

The pattern is consistent: grepShitDone's advantage is highest the **first time a code domain is explored in a session**. Once Claude has seen the relevant files, they're cached and both conditions perform equivalently. If you regularly run long GSD sessions across unfamiliar parts of a codebase, the savings add up. If your sessions are short and domain-specific, the benefit is modest.

---

### Study 2 — Search mechanism comparison (semantic vs keyword)

This measures grepai's retrieval quality directly: 12 real engineering tasks, comparing the context returned by `grepai search` (top-5 chunks) against what keyword grep surfaces (top-8 file matches, full reads). This is the underlying mechanism that drives Study 1's results.

| Task | grepShitDone | Grep baseline | Reduction |
|:-----|-------------:|--------------:|:---------:|
| Humanization pipeline entry point | 2,393 | 26,836 | **91%** |
| Anthropic API auth token handling | 1,666 | 46,196 | **96%** |
| Cron job registration & scheduling | 2,284 | 26,575 | **91%** |
| Tweet delivery to Discord | 1,943 | 26,509 | **93%** |
| Story buffer read/write/seed | 1,985 | 10,439 | **81%** |
| Oracle provisioner retry logic | 1,661 | 29,246 | **94%** |
| Morning brief build & send | 1,863 | 2,461 | **24%** |
| Build queue status tracking | 1,640 | 32,831 | **95%** |
| AI text scoring algorithm | 2,408 | 40,976 | **94%** |
| YouTube transcript extraction | 1,743 | 44,422 | **96%** |
| Discord rate-limit notification | 1,977 | 33,120 | **94%** |
| Media queue processing pipeline | 1,417 | 15,001 | **91%** |
| **TOTAL** | **22,984 tokens** | **334,616 tokens** | **93%** |

**14.6× less context when using semantic search vs naive keyword matching.**

> Why does Study 1 show 28% and Study 2 show 93%? GSD doesn't do naive keyword matching — it uses prompt caching, which already amortizes the cost of reading files across turns. Study 2 measures the raw search mechanism in isolation. Study 1 measures what actually changes in a real GSD session.

---

### Retrieval accuracy

How often grepai returns the correct file in its top k results (12-task battery):

```
P@1   58%   (7/12)   correct file is the #1 result
P@3   83%   (10/12)  correct file appears in top 3
P@5   83%   (10/12)  correct file appears in top 5
```

The 2 tasks missing at P@3/P@5 had target files in a **separate repo not included in the index** — correctly returning nothing rather than a wrong match. The 5 P@1 misses that recovered at P@3 surfaced an equally valid alternative file first.

---

### Query latency

```
Cold start (daemon spin-up)    ~980ms
Warm queries (daemon running)   ~50ms  (46–54ms over 5 runs)
```

---

## Install

```bash
git clone https://github.com/cyne-wulf/grepShitDone
cd grepShitDone
./install.sh
```

Start a new Claude Code session. Done.

### Prerequisites

- [grepai](https://github.com/yoanbernabeu/grepai) installed and on your PATH
- [GSD](https://github.com/glittercowboy/get-shit-done) installed in Claude Code
- Your project indexed: `cd your-project && grepai init`

---

## How it works

A `SessionStart` hook fires at the start of every Claude Code session:

1. **Exits silently** if `grepai` isn't installed — zero overhead, nothing breaks
2. **Starts the `grepai watch` daemon** if it isn't already running (keeps the index fresh)
3. **Writes a GSD-compatible adapter** to `.agents/skills/grepai/SKILL.md` in your project
4. **Adds that path to `.gitignore`** so the generated file isn't committed

GSD's researcher and executor agents automatically scan `.agents/skills/` on boot and load any `SKILL.md` they find. The adapter teaches them to reach for `grepai search` before falling back to `Grep`. The main orchestrator gets the same rules via `~/.claude/CLAUDE.md`.

---

## Benchmark methodology

<details>
<summary>Full details</summary>

**Environment**
- Ubuntu 24.04, 64GB RAM, NVIDIA RTX 3070
- Codebase: single production repo, 104 files / 768 chunks / 4.7MB index
- Embedding provider: Ollama (`nomic-embed-text:latest`, local, port 11434)

**Study 1 — Instrumented GSD sessions**
- Each task run twice with `claude --print --output-format json`
- Condition A: `.agents/skills/grepai/` removed (no adapter)
- Condition B: adapter installed at `.agents/skills/grepai/SKILL.md`
- Token counts from API response: `cache_creation_input_tokens + cache_read_input_tokens`
- Cost from `total_cost_usd` in API response
- Tasks were genuine research tasks with real output written to `.planning/`
- Cache state reflects real usage — task 1 was cold (fresh session), tasks 2–3 ran after task 1 had populated the cache

**Study 2 — Search mechanism comparison**
- `grepai search "<query>" --json -n 5` per task
- Token cost = total length of `content` fields in returned chunks ÷ 4
- Grep baseline = `grep -rl -E "<keywords>" --include="*.js,*.py,*.sh"` top-8 matches, full file sizes ÷ 4
- Grep baseline is conservative — real sessions without semantic search typically revisit files across related tasks
- 12 tasks drawn from real agent workflows, written in natural language before any searches were run (no query tuning)
- Ground truth determined by manual codebase inspection before benchmarking

**Why the two studies give different numbers**
GSD's prompt caching amortizes file-read costs across turns within a session. Study 2 measures the raw search mechanism without caching. Study 1 measures what actually changes in a real GSD session, including caching effects. The cold-run result (28%) is the more operationally relevant number for most GSD users.

</details>

---

## Compatibility notes

| Problem | How it's handled |
|:--------|:-----------------|
| GSD subagents can't invoke the `Skill` tool | Adapter is plain Markdown — no invocation needed |
| GSD looks in `.agents/skills/`, not `.claude/skills/` | Hook writes to the right place each session |
| grepai daemon not running at session start | Hook starts it automatically |
| grepai docs say "never use Grep"; GSD uses it internally | Adapter explicitly exempts GSD orchestration grep calls |
| grepai claims to replace WebSearch | Adapter scopes it to local code only |

---

## Update

```bash
cd grepShitDone
git pull
./install.sh
```

---

## What gets installed

```
~/.claude/
└── grepshitdone/
    ├── hook.sh       ← SessionStart hook (registered in settings.json)
    └── SKILL.md      ← adapter template (copied into projects each session)
```

An entry is appended to `~/.claude/CLAUDE.md`. Nothing else on your system is touched.
