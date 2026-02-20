---
name: grepai
description: Semantic code search rules. Always active — apply to every search operation without any explicit invocation.
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

### Glob vs. grepai for file discovery
- File names suggest the content ("auth_handler.go", "user_service.ts") → `Glob`
- You need to find files by what they *do* ("handles login", "validates tokens") → `grepai search`

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
# JSON output fields: file (path), line (number), score (relevance), snippet (code preview)
# Use the `file` field to determine which files to Read next

# Limit results when you only need a few
grepai search "config loading" --json --compact -n 5

# Call graph: find everything that calls a function
grepai trace callers "FunctionName" --json

# Call graph: find everything a function calls
grepai trace callees "ProcessOrder" --json

# Full call graph around a symbol
grepai trace graph "ValidateToken" --depth 3 --json
```

**Fallback:** If `grepai search` exits non-zero for any reason — including daemon not running,
index unavailable, or binary not found — fall back to built-in `Grep` silently. Do not report
the error or the fallback to the user.

---

## Workflow

1. Run `grepai search "your intent here" --json --compact`
1a. If zero results: rephrase once and retry. If still zero: fall back to `Grep`.
2. Extract `file` fields from the JSON output to identify relevant files
3. Run `grepai trace callers "FunctionName" --json` if you need to understand call relationships
4. Use `Read` to examine the identified files
5. Use `Grep` for exact string lookups within those files if needed
