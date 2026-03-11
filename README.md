# grepShitDone

> Bridges [grepai](https://github.com/yoanbernabeu/grepai) semantic search into [GSD (Get Shit Done)](https://github.com/glittercowboy/get-shit-done) workflows.

Install once. Never think about it again.

---

## What it does

Without grepShitDone, a GSD agent finding relevant code has two options: read a pile of files and hope the right one is in there, or ask you. Both are expensive. Token costs accumulate fast across large codebases and repeated sessions.

**grepShitDone gives GSD agents a third option: ask the index.** A single `grepai search` query returns the 5 most relevant code chunks from your entire codebase. Same answer. A fraction of the context.

---

## Performance

Benchmarked on a real production codebase — **104 files, 768 indexed chunks, ~45,000 lines of JavaScript, Python, and shell** — against the unmodified baseline (keyword grep → full file reads).

### Token efficiency — 12-task split test

| Task | With grepShitDone | Without | Reduction |
|:-----|------------------:|--------:|:---------:|
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
| **TOTAL** | **22,984 tokens** | **334,616 tokens** | **93.1%** |

**14.6× less context per session. 93% token reduction across 12 real engineering tasks.**

> Token counts are `char_count / 4` estimates. "Without" baseline = full file reads for top-8 keyword matches per query — conservative; real sessions typically read more.

---

### Retrieval accuracy

How often grepShitDone returns the correct file in its top k results:

```
P@1   58%   (7/12)   correct file is the #1 result
P@3   83%   (10/12)  correct file appears in top 3
P@5   83%   (10/12)  correct file appears in top 5
```

The 2 tasks missing at P@3/P@5 had target files in a **separate repo not included in the index** — grepShitDone correctly returned nothing rather than surfacing a wrong match. The 5 tasks that recovered from P@1 to P@3 returned an equally valid alternative file first (e.g. `story-buffer.json` ranked above `tweet-batch.js` for a story buffer query — both are correct).

---

### Query latency

```
Cold start (daemon spin-up)   ~980ms
Warm queries (daemon running)  ~50ms  (46–54ms across 5 runs)
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
2. **Starts the `grepai watch` daemon** if it isn't already running (keeps the index fresh)
3. **Writes a GSD-compatible adapter** to `.agents/skills/grepai/SKILL.md` in your project
4. **Adds that path** to `.gitignore` so the generated file isn't committed

GSD subagents automatically scan `.agents/skills/` on boot and load any `SKILL.md` they find. The adapter teaches them to reach for `grepai search` before falling back to `Grep`. The main orchestrator gets the same rules via `~/.claude/CLAUDE.md`.

---

## Benchmark methodology

<details>
<summary>Full details</summary>

**Environment**
- Ubuntu 24.04, 64GB RAM, NVIDIA RTX 3070
- Codebase: single production repo, 104 files / 768 chunks / 4.7MB index
- Embedding provider: Ollama (`nomic-embed-text:latest`, local, port 11434)
- Token counting: `wc -c` byte counts divided by 4 (standard approximation)

**With grepShitDone**
- `grepai search "<query>" --json -n 5` per task
- Token cost = total length of `content` fields in the returned chunks

**Without grepShitDone (baseline)**
- `grep -rl -E "<keywords>" --include="*.js,*.py,*.sh"` per task, top 8 file matches
- Token cost = sum of full file sizes for all matched files
- Conservative — real sessions without semantic search typically read more files, and revisit the same files across related tasks

**Task design**
- 12 tasks drawn from real agent workflows on the test codebase
- Natural language queries written before running any searches — no tuning to improve scores
- Ground truth ("expected file") determined by manual codebase inspection before benchmarking
- Task 8 is excluded from accuracy calculations: the target file lives in a separate repo that was not indexed — the correct behavior is to return no match, which is what happened

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

The next session picks up the updated adapter automatically.

---

## What gets installed

```
~/.claude/
└── grepshitdone/
    ├── hook.sh       ← SessionStart hook (registered in settings.json)
    └── SKILL.md      ← adapter template (copied into projects each session)
```

An entry is appended to `~/.claude/CLAUDE.md`. Nothing else on your system is touched.
