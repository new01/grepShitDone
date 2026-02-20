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

### Use `Glob` when:
- File path patterns: `**/*.go`, `src/**/*.ts`, `**/test_*.py`
- Listing files by extension or directory structure

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
