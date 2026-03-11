# grepShitDone

> Semantic code search for [GSD (Get Shit Done)](https://github.com/glittercowboy/get-shit-done) workflows — powered by [grepai](https://github.com/yoanbernabeu/grepai).

Install once. Your GSD agents find the right code on the first try instead of reading everything.

---

## The problem

When a GSD agent needs context, it either reads too much (whole files, wrong files) or asks you where things are. Both are expensive. Token costs accumulate fast on large codebases — especially across repeated agent sessions.

**grepShitDone replaces broad file-reading with targeted semantic search.** Instead of surfacing 8 files and reading all of them, a single `grepai search` query returns the 5 most relevant code chunks. Same answer. A fraction of the context.

---

## Performance

Split-tested against vanilla GSD (grep-based file discovery → full file reads) on a real production codebase: **104 files, 768 indexed chunks, ~45,000 lines of JavaScript, Python, and shell**.

### Token efficiency — 12 task battery

| Task | grepShitDone | Vanilla GSD | Reduction |
|:-----|-------------:|------------:|:---------:|
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
| **TOTAL** | **22,984** | **334,616** | **93%** |

> All token counts are `char_count / 4` estimates. Vanilla baseline = full file reads for top-8 grep matches per query. Both measurements are conservative — real sessions read more.

**14.6× less context. 93.1% token reduction across 12 real engineering tasks.**

---

### Retrieval accuracy — Precision @ k

How often does the correct file appear in the top k results:

```
P@1   58%   (7 / 12)   — right file is the top result
P@3   83%   (10 / 12)  — right file is in top 3
P@5   83%   (10 / 12)  — right file is in top 5
```

The 2 misses at P@3/P@5 were files in a **separate repo not included in the index** — the tool correctly returned "nothing relevant here" rather than hallucinating a match. The 5 P@1 misses that recovered by P@3 were cases where an equally valid alternative file ranked first (e.g. `story-buffer.json` instead of `tweet-batch.js` for a query about the story buffer — both are correct answers).

---

### Query latency

```
Cold start (daemon spin-up):  ~980ms
Warm queries (daemon running): ~50ms average (46–54ms across 5 runs)
```

After the first query of a session, overhead is negligible.

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
2. **Starts the `grepai watch` daemon** if it isn't already running (keeps index fresh)
3. **Writes a GSD-compatible adapter** to `.agents/skills/grepai/SKILL.md` in your project
4. **Adds `.agents/skills/grepai/`** to `.gitignore` so generated files don't get committed

GSD subagents automatically scan `.agents/skills/` on boot and load any `SKILL.md` they find. The adapter teaches them to reach for `grepai search` before falling back to `Grep`. The main Claude orchestrator gets the same rules via `~/.claude/CLAUDE.md`.

---

## Benchmark methodology

**Environment**
- Machine: Ubuntu 24.04, 64GB RAM, NVIDIA RTX 3070
- Codebase: single production repo, 104 files / 768 chunks / 4.7MB index
- Embedding provider: Ollama (`nomic-embed-text:latest`, local, port 11434)
- Measurement: wall-clock timing + `wc -c` for byte counts; tokens approximated as `chars / 4`

**grepShitDone baseline**
- `grepai search "<query>" --json -n 5` per task
- Token cost = sum of `content` field lengths across returned chunks

**Vanilla GSD baseline**
- `grep -rl -E "<keywords>" --include="*.js,*.py,*.sh"` per task, top 8 matches
- Token cost = sum of full file sizes for all matched files
- This is *conservative* — real sessions often read more files, or read the same file multiple times across related tasks

**Task design**
- 12 tasks drawn from real agent workflows on the test codebase
- Tasks were written in natural language before running any searches — no query tuning
- "Expected file" was determined by manually inspecting the codebase before running benchmarks
- Accuracy marked correct if the expected file appears in the result set; task 8 is excluded from accuracy calculations (target file was in a separate un-indexed repo — correctly not returned)

---

## Compatibility notes

| Problem | How this is solved |
|:--------|:-------------------|
| GSD subagents can't invoke the `Skill` tool | Adapter is plain text — no invocation needed |
| GSD looks in `.agents/skills/`, not `.claude/skills/` | Hook writes adapter to the right place each session |
| grepai daemon not running at session start | Hook starts it automatically |
| grepai's docs say "never use Grep"; GSD uses `grep` internally | Adapter explicitly exempts GSD orchestration calls |
| grepai claims to replace WebSearch | Adapter scopes grepai to local code only |

---

## Update

```bash
cd grepShitDone
git pull
./install.sh
```

The next session picks up the updated adapter automatically.

---

## What gets installed

```
~/.claude/
└── grepshitdone/
    ├── hook.sh       ← SessionStart hook (registered in settings.json)
    └── SKILL.md      ← adapter template (copied into projects each session)
```

An entry is appended to `~/.claude/CLAUDE.md`. Nothing else on your system is modified.
