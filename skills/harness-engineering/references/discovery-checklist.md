# Phase 1: Discovery Checklist

**Goal:** Understand what this project IS before prescribing anything.

In v0.3.0 this phase runs as ONE parallel batch (10 calls in a single message). See "Parallel Execution Recipe" below for copy-paste scout prompts. Sections 1.1-1.10 describe what each call covers.

## 1.1 Detect Language & Framework

```bash
# File extensions reveal primary language
tldr tree . --depth 1

# Package manifests reveal framework
# Look for: package.json, go.mod, Cargo.toml, pyproject.toml, pom.xml,
#           build.gradle, Gemfile, mix.exs, composer.json, etc.
```

Read the manifest file to identify:
- Primary language and version
- Framework (if any)
- Build tool
- Test framework
- Linter/formatter configuration

## 1.2 Detect Architecture

```bash
tldr tree . --depth 3
tldr arch .
tldr structure . --lang <detected>
```

Don't assume layers. **Discover** them:
- What directories exist at the top level?
- How is code organized? (by feature? by layer? by domain?)
- What are the dependency directions between modules?
- Are there clear boundaries (interfaces, contracts)?

## 1.3 Detect Coding Patterns

Read 5-8 representative source files spanning different parts of the codebase. For each, note:

- **Naming**: How are files, functions, types, variables named?
- **Error handling**: try/catch? Result types? Error codes? Panic?
- **Dependency management**: Constructor injection? Global imports? Service locator?
- **State management**: Where does state live? How is it passed?
- **Async patterns**: Callbacks? Promises? Channels? Coroutines?
- **Type usage**: Strict types? Any/interface{}? Generics?
- **Logging**: What library? What levels? What format?
- **Validation**: Where does input validation happen? What library?

## 1.4 Detect Testing Patterns

```bash
# Find test files
tldr search "test" . --ext <test_extension>
```

Read 2-3 test files to understand:
- Test framework and assertion style
- How fixtures/mocks are set up
- Integration vs unit test separation
- Test data patterns (factories? fixtures? inline?)

## 1.5 Detect CI/CD & Quality Checks

Look for: `.github/workflows/`, `Jenkinsfile`, `.gitlab-ci.yml`, `Makefile`, `justfile`, etc.

What checks already run? What's missing?

## 1.6 Detect Unwritten Rules

These are patterns that are **consistent across the codebase** but not documented anywhere:

- Do all API handlers follow the same structure?
- Is there a consistent way to add a new feature?
- Are there implicit naming conventions (e.g., `*_handler.go`, `use*.ts`)?
- Are certain patterns always paired? (e.g., every service has a matching interface)
- What patterns are NEVER violated across the codebase?

**Method:** Compare 3+ files of the same "type" and extract what's identical in structure.

## 1.7 Research Best Practices

After detecting the stack, research current best practices for that specific language/framework. **Fire BOTH ctx7 AND WebSearch in parallel** (single message, two concurrent tool calls), then synthesize their outputs:

```bash
# In a single oracle invocation, issue both in parallel:
#   - ctx7 (or perplexity MCP): authoritative library docs + API reference
#   - WebSearch: community conventions, recent blog posts, RFCs, GitHub issues
```

Why both: ctx7 catches official/authoritative recommendations; WebSearch catches community drift, recent vulnerabilities, and idioms not yet in docs. Running them concurrently costs the same wall time as either alone but doubles coverage.

Compare what the project does vs. what the ecosystem recommends. The harness should encode **the project's actual conventions** (even if they differ from ecosystem defaults), but flag divergences for the wiki.

## 1.8 Detect Data Models (wiki scout)

Find schema files and entity definitions. Look for: `prisma/schema.prisma`, `**/models/`, `**/entities/`, `**/schemas/`, SQLAlchemy models, Mongoose schemas, Gorm structs, ActiveRecord migrations, JPA `@Entity`, etc.

Output: entity list with `{name, file, fields_sample, relationships}`. Feeds `harness/wiki/data-models.md`.

## 1.9 Detect Critical Paths (wiki scout)

Trace entry points to primary business flows. Look at request handlers (controllers, routes), CLI entry points (`main` / `cmd/`), cron jobs, message consumers. For each entry, identify which 3-5 files are touched downstream.

Output: `{entry_points, primary_flows: [{name, files_touched, layers}], modification_hotspots}`. Feeds `harness/wiki/critical-paths.md`.

## 1.10 Detect External Services (wiki scout)

Grep for SDK imports (`stripe`, `aws-sdk`, `redis`, `kafka`, `postgres`, `elasticsearch`, `openai`, etc.). Read env-var config (`.env.example`, `config/`). Look for timeout / retry / circuit-breaker patterns.

Output: `{services: [{name, purpose, config_location}], env_vars, timeout_retry_patterns}`. Feeds `harness/wiki/external-services.md`.

---

## Parallel Execution Recipe (v0.3.0)

In one message, issue these 10 tool calls concurrently:

### Call 1 — Bash batch (1.1 + 1.5 fast detection)

```bash
tldr tree --depth 2 . 2>/dev/null
echo '---'
tldr arch . 2>/dev/null
echo '---'
tldr structure . --lang ${DETECTED_LANG:-typescript} 2>/dev/null | head -100
echo '---'
ls package.json go.mod pyproject.toml Cargo.toml Gemfile pom.xml build.gradle mix.exs composer.json 2>/dev/null
echo '---'
ls -la .github/workflows Jenkinsfile Makefile justfile 2>/dev/null
echo '---'
git log --oneline -30 2>/dev/null
```

### Call 2 — scout (1.2 architecture)

```
You are a codebase architect. Given the tldr output (in context), identify
the project's architectural layers.

Return JSON ONLY:
{
  "scout_id": "1.2",
  "status": "ok" | "no_evidence",
  "summary": "≤200 word prose summary",
  "structured": {
    "layers": [{"name": "<layer>", "dir": "<path>", "deps": ["<other layer>"]}],
    "boundary_table": [{"from": "<layer>", "may_call": [...], "must_not_call": [...]}]
  },
  "evidence_files": ["<paths examined>"]
}
```

### Call 3 — scout (1.3 coding patterns)

```
Read 5-8 representative source files from different parts of the codebase.
Extract: naming conventions (files/functions/types/constants), error-handling
pattern, async style, type discipline, logging library + format, validation.

Return JSON ONLY:
{
  "scout_id": "1.3",
  "status": "ok",
  "summary": "...",
  "structured": {
    "naming": {"files": "...", "fns": "...", "types": "...", "consts": "..."},
    "error_handling": "...",
    "async_pattern": "...",
    "type_usage": "...",
    "logging": {"library": "...", "format": "..."},
    "validation": "..."
  },
  "evidence_files": [...]
}
```

### Call 4 — scout (1.4 testing)

```
Find 2-3 test files. Identify framework + assertion style + mock/fixture
pattern + file naming template.

Return JSON ONLY:
{
  "scout_id": "1.4",
  "status": "ok" | "no_evidence",
  "structured": {
    "framework": "...",
    "assertion_style": "...",
    "mock_pattern": "...",
    "file_template": "<10-line skeleton>"
  },
  "evidence_files": [...]
}
```

If no tests exist at all, status = "no_evidence".

### Call 5 — scout (1.5 git + CI)

```
Read git log + CI configs (.github/workflows/, Jenkinsfile, Makefile, justfile).

Return JSON ONLY:
{
  "scout_id": "1.5",
  "status": "ok",
  "structured": {
    "branch_strategy": "...",
    "commit_conventions": "<conventional-commits | imperative | other>",
    "ci_checks": {
      "build": "<exact command, e.g. 'npm run build'>",
      "lint": "<exact command>",
      "test": "<exact command>"
    }
  },
  "evidence_files": [...]
}
```

### Call 6 — scout (1.6 unwritten rules)

```
Compare 3+ files of the same "type" in each detected layer. Find patterns
that are CONSISTENT across all of them — these are unwritten invariants.
Also find patterns NEVER violated.

Return JSON ONLY:
{
  "scout_id": "1.6",
  "status": "ok" | "no_evidence",
  "structured": {
    "invariants": ["<observed-consistent rule>", ...],
    "anti_patterns": ["<never-done in codebase>", ...]
  },
  "evidence_files": [...]
}
```

### Call 7 — oracle (1.7 best practices) — runs ctx7 + WebSearch in parallel

```
Inside this oracle invocation, issue TWO tool calls in a single message:
  - ctx7 (or perplexity MCP) — authoritative docs for the detected stack
    (e.g., Next.js 15, FastAPI, Go std lib).
  - WebSearch — community conventions, recent blog posts, RFCs, GitHub
    discussions, security advisories for the same stack.

Wait for both, then synthesize. Compare against the project's actual
patterns from scouts 1.3 / 1.6. ctx7 captures official recommendations;
WebSearch captures recent community drift and idioms not yet in docs.
Running them concurrently costs the same wall time as either alone but
doubles coverage.

Return JSON ONLY:
{
  "scout_id": "1.7",
  "status": "ok" | "no_evidence",
  "sources": {
    "ctx7":      "<one-line summary or 'no_match'>",
    "websearch": "<one-line summary or 'no_results'>"
  },
  "structured": {
    "ecosystem_recommendations": [...],
    "divergences": [{"area": "...", "project_does": "...", "ecosystem_says": "...", "verdict": "intentional|outdated|unclear", "source": "ctx7|websearch|both"}]
  }
}
```

Time-limit 60s for the combined call. If BOTH sources fail (ctx7 no_match
+ WebSearch no_results), return `status: no_evidence` and skip. If only
one source succeeds, return `status: ok` with the available data and mark
the failed source explicitly in `sources`.

### Call 8 — scout (1.8 data models, wiki)

```
Find schema/model files: prisma/schema.prisma, **/models/, **/entities/,
SQLAlchemy, Mongoose, Gorm structs, ActiveRecord migrations, JPA @Entity.

Return JSON ONLY:
{
  "scout_id": "1.8",
  "status": "ok" | "no_evidence",
  "structured": {
    "entities": [{"name": "...", "file": "...", "fields_sample": [...]}],
    "schema_location": "...",
    "migration_pattern": "...",
    "relationships": [{"from": "...", "to": "...", "kind": "<has_many|belongs_to|...>"}]
  },
  "evidence_files": [...]
}
```

### Call 9 — scout (1.9 critical paths, wiki)

```
Identify entry points (HTTP handlers, CLI commands, cron jobs, message
consumers, main functions). For each, trace which 3-5 files are touched
downstream. Identify hotspots that get modified frequently.

Return JSON ONLY:
{
  "scout_id": "1.9",
  "status": "ok" | "no_evidence",
  "structured": {
    "entry_points": [{"name": "...", "file": "..."}],
    "primary_flows": [{"name": "...", "files_touched": [...], "layers": [...]}],
    "modification_hotspots": [...]
  },
  "evidence_files": [...]
}
```

### Call 10 — scout (1.10 external services, wiki)

```
Grep for external-service SDK imports (stripe, aws-sdk, redis, kafka,
postgres, elasticsearch, openai, twilio, sendgrid, etc.). Read env var
config (.env.example, config/). Look for timeout / retry / circuit-breaker
patterns in calling code.

Return JSON ONLY:
{
  "scout_id": "1.10",
  "status": "ok" | "no_evidence",
  "structured": {
    "services": [{"name": "...", "purpose": "...", "config_location": "..."}],
    "env_vars": [...],
    "timeout_retry_patterns": [{"service": "...", "pattern": "..."}]
  },
  "evidence_files": [...]
}
```

---

## Failure handling: batched follow-up

After all 10 calls return, collect scouts where `status: no_evidence`. Issue ONE follow-up `AskUserQuestion` listing each:

```
Scouts couldn't find evidence for: {list}

For each, pick:
  - Skip (use default / empty section for that artifact)
  - Provide hints (paste 1-2 file paths)
  - Mark not-applicable (record in engineering-structure.md)
```

Don't block per-scout. One question covers all failures.

---

## Synthesizing DISCOVERY

Merge all `status: ok` outputs into one in-context blob:

```
DISCOVERY = {
  lang, framework, build_tool, test_framework,            // from call 1 + 1.5
  architecture: { layers, boundary_table },               // from 1.2
  coding: { naming, error_handling, async_pattern, ... }, // from 1.3
  testing: { framework, assertion_style, ... },           // from 1.4
  ci_checks: { build, lint, test },                       // from 1.5
  invariants, anti_patterns,                              // from 1.6
  best_practices: { recommendations, divergences },       // from 1.7
  data_models: { entities, relationships },               // from 1.8
  critical_paths: { entry_points, primary_flows },        // from 1.9
  external_services: { services, env_vars }               // from 1.10
}
```

DISCOVERY stays in conversation context. Phase 2 Write batch reads from it. No disk write.
