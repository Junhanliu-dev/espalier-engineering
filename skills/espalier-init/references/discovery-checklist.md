# Phase 1: Discovery Checklist

**Goal:** Understand what this project IS before prescribing anything.

This phase runs as ONE parallel batch (11 calls in a single message). See "Parallel Execution Recipe" below for copy-paste scout prompts. Sections 1.1-1.10 describe what each call covers.

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
- **Comments**: Density (sparse/heavy)? Docstring convention (JSDoc / docstrings / none)? What earns a comment (constraints? nothing?)?

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

Compare what the project does vs. what the ecosystem recommends. Espalier should encode **the project's actual conventions** (even if they differ from ecosystem defaults), but flag divergences for the wiki.

## 1.8 Detect Data Models (wiki scout)

Find schema files and entity definitions. Look for: `prisma/schema.prisma`, `**/models/`, `**/entities/`, `**/schemas/`, SQLAlchemy models, Mongoose schemas, Gorm structs, ActiveRecord migrations, JPA `@Entity`, etc.

Output: entity list with `{name, file, fields_sample, relationships}`. Feeds `espalier/wiki/data-models.md`.

## 1.9 Detect Critical Paths (wiki scout)

Trace entry points to primary business flows. Look at request handlers (controllers, routes), CLI entry points (`main` / `cmd/`), cron jobs, message consumers. For each entry, identify which 3-5 files are touched downstream.

Output: `{entry_points, primary_flows: [{name, files_touched, layers}], modification_hotspots}`. Feeds `espalier/wiki/critical-paths.md`.

## 1.10 Detect External Services (wiki scout)

Grep for SDK imports (`stripe`, `aws-sdk`, `redis`, `kafka`, `postgres`, `elasticsearch`, `openai`, etc.). Read env-var config (`.env.example`, `config/`). Look for timeout / retry / circuit-breaker patterns.

Output: `{services: [{name, purpose, config_location}], env_vars, timeout_retry_patterns}`. Feeds `espalier/wiki/external-services.md`.

## 1.11 Detect Security Surface

Find the trust boundary and the sensitive fields. Identify the entry points where client data enters (HTTP handlers, GraphQL resolvers, RPC, server actions, queue consumers); how the backend establishes caller identity (session / JWT / auth middleware); how object ownership is enforced today before a load or mutate (pattern + `file:line`, or NONE); where request validation happens (library + layer). Then scan schemas and handlers for fields on the five risk axes — money (`price`, `amount`, `balance`, `stock`), identity (`userId`, `accountId`), permission (`role`, `isAdmin`, `scope`), owner (`orderId`, `tenantId`), state (`status`, `approved`) — plus project-specific names.

Output: `{entry_points, identity_pattern, ownership_pattern, validation, sensitive_fields, project_conventions}`. Feeds three fill targets in `espalier/rules/security-standards.md`: the trust-boundary bullets (entry_points / identity_pattern / ownership_pattern / validation), the per-axis taxonomy cells (sensitive_fields), and the Project-Specific Security Conventions section (project_conventions).

---

## Parallel Execution Recipe

In one message, issue these 11 tool calls concurrently:

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
pattern, async style, type discipline, logging library + format, validation,
comment conventions (density / docstring style / what earns a comment).

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
    "validation": "...",
    "comments": {"density": "...", "docstrings": "...", "what_gets_commented": "..."}
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

### Call 5 — scout (1.5 git + CI + deploy)

```
Read git log + CI configs (.github/workflows/, Jenkinsfile, Makefile, justfile).
Also look for deploy configuration: deploy workflows/jobs, Procfile, Dockerfile +
compose/k8s manifests, fly.toml, vercel.json, serverless.yml — and any health/
readiness endpoint the app exposes (grep routes for /health, /healthz, /ready,
/ping). Deploy discovery is OPTIONAL — when the repo has no deploy config, set
"deploy": null (do NOT invent one; Stage 9 records a clean skip).

ci_checks values must be commands that exist TODAY (verified in a manifest
script, Makefile target, or CI step). A kind with no command — no lint
configured, no build step, no test runner — is null, never guessed: an
invented command lands in the pre-push gate and blocks every push.

Return JSON ONLY:
{
  "scout_id": "1.5",
  "status": "ok",
  "structured": {
    "branch_strategy": "...",
    "commit_conventions": "<conventional-commits | imperative | other>",
    "ci_checks": {
      "build": "<exact command, e.g. 'npm run build'> | null",
      "lint": "<exact command> | null",
      "test": "<exact command> | null"
    },
    "deploy": {
      "mechanism": "<e.g. 'GitHub Actions deploy.yml on main' | 'fly deploy'>",
      "command": "<exact command, or 'automatic on merge'>",
      "health_check": "<URL path or command, e.g. 'GET /healthz'>",
      "environment": "<staging|production|both — what a merged change reaches>"
    }
  },
  "evidence_files": [...]
}
```

`deploy` is `null` when no deploy config exists — never guessed. Same rule per
`ci_checks` key: a repo with no lint (or no build step, or no test runner) gets
`null` for that key, never an invented command — Phase 2 substitutes a clean
no-op (build/lint) or an actionable fail-closed stub (test) into the push gate.

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

### Call 11 — scout (1.11 security surface)

```
Find the trust boundary and sensitive fields for security-standards.md.
Identify: (a) entry points where client data enters (controllers / routes /
resolvers / RPC / server actions / queue consumers); (b) how caller identity is
established (session / JWT / auth middleware — pattern + file:line); (c) how object
ownership is enforced before a load or mutate (pattern + file:line, or "NONE
FOUND"); (d) where request validation happens (library + layer); (e) existing
security conventions the codebase already follows (e.g. "all controllers call
requireOwner(ctx, id) before load", "prices come from PriceService.quote()"), each
with a file:line. Then list fields on the money / identity / permission / owner /
state axes, project-specific names included.

Return JSON ONLY:
{
  "scout_id": "1.11",
  "status": "ok" | "no_evidence",
  "structured": {
    "entry_points": [{"kind": "...", "example": "file:line"}],
    "identity_pattern": "...",
    "ownership_pattern": "... | NONE FOUND",
    "validation": {"library": "...", "layer": "..."},
    "sensitive_fields": [{"name": "...", "axis": "money|identity|permission|owner|state"}],
    "project_conventions": [{"pattern": "...", "example": "file:line"}]
  },
  "evidence_files": [...]
}
```

---

## Failure handling: batched follow-up

After all 11 calls return, collect scouts where `status: no_evidence`. Issue ONE follow-up `AskUserQuestion` listing each:

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
  deploy: { mechanism, command, health_check, environment } | null,  // from 1.5 (null = no deploy config)
  invariants, anti_patterns,                              // from 1.6
  best_practices: { recommendations, divergences },       // from 1.7
  data_models: { entities, relationships },               // from 1.8
  critical_paths: { entry_points, primary_flows },        // from 1.9
  external_services: { services, env_vars },              // from 1.10
  security: { entry_points, identity_pattern, ownership_pattern, validation, sensitive_fields, project_conventions }  // from 1.11
}
```

DISCOVERY stays in conversation context. Phase 2 Write batch reads from it. No disk write.
