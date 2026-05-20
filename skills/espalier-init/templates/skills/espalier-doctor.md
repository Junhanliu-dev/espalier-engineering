---
name: espalier-doctor
description: Periodically re-scout the codebase to catch Espalier-artifact drift that file-diff detection misses — silent refactors and pre-clone drift
---

# Espalier Doctor

A periodic deep check. Catches what the post-merge file-diff detector and the
reviewer cannot: silent refactors that change no file structure, and drift that
landed before this clone existed (the drift sidecar is per-clone).

The doctor only FLAGS — it writes sidecar rows and a report, it never edits a
doc. Refresh is always `/espalier-prune`.

## When to Use

- "/espalier-doctor" — run a drift scan now
- Surfaced by the Stage 0 pre-flight when `doctor_due()` is true
- A non-blocking reminder at `git push` time when a scan is overdue

## Trigger

```
/espalier-doctor [--quick | --full | --since <sha>]
```

| Mode | Scope | Cost |
|------|-------|------|
| `--quick` (default) | re-scout architecture, CI, data-models, critical-paths, external-services | ~3 min |
| `--full` | every embedded scout (also coding-patterns, unwritten-rules, per-layer specs) | ~8 min |
| `--since <sha>` | only re-scout layers with files touched since `<sha>` | varies |

## What It Does

```bash
. espalier/hooks/drift-helpers.sh
```

For each artifact in scope (see Scout Mapping):

1. Spawn the matching scout (prompts embedded below) against the CURRENT codebase.
2. Two-way diff the scout's proposed content vs the current artifact file.
3. If MATERIALLY different, flag it:
   ```bash
   mark_stale "<artifact>" "$(git rev-parse HEAD)" "doctor: scout drift"
   ```
   If the scout confirms the artifact is current AND it carries a stale row
   from an earlier false positive, retire that row:
   ```bash
   clear_stale "<artifact>"
   ```

On completion, stamp the run and write a report:

```bash
doctor_stamp "$(git rev-parse HEAD)"
```

`doctor_stamp` records the run in the gitignored `espalier/.doctor-last-run`, so
`doctor_due()` resets. Write a timestamped human summary to the gitignored
`espalier/.drift-report.md`: artifacts scanned, flagged, confirmed-current.

The doctor never edits an artifact. To apply a refresh, run `/espalier-prune`.

## Cadence

The cadence is chosen at `/espalier-init` (Phase 0 Q3) and stored in the tracked
`espalier/.doctor-cadence` (one line, e.g. `cadence: weekly`):

| `cadence:` | `doctor_due()` fires |
|-----------|----------------------|
| `every-change` | every Stage 0 pre-flight |
| `weekly` | first activity after 7 days |
| `monthly` | first activity after 30 days |
| `manual` | never automatically — only an explicit `/espalier-doctor` |

`doctor_due()` (in `drift-helpers.sh`) compares the tracked cadence against the
gitignored `espalier/.doctor-last-run` stamp. It is activity-gated — an idle
repo never triggers a scan (no commits = no drift). It is checked at the
`/espalier` and `/espalier-fix` Stage 0 pre-flights and as a non-blocking
reminder in `pre-push-gate.sh`. To change the cadence, edit `.doctor-cadence`
directly — bootstrap writes it once and never auto-rewrites it.

## Scout Mapping

| Artifact | Scout | In `--quick`? |
|----------|-------|---------------|
| `rules/engineering-structure.md` + `wiki/architecture.md` | 1.2 | yes |
| `rules/development-process.md` | 1.5 | yes |
| `wiki/data-models.md` | 1.8 | yes |
| `wiki/critical-paths.md` | 1.9 | yes |
| `wiki/external-services.md` | 1.10 | yes |
| `rules/coding-standards.md` | 1.3 + 1.6 (merge before diff) | `--full` only |
| `skills/espalier-coding/specs/{layer}.md` | per-layer spec scout | `--full` only |

## Embedded Scout Prompts

These are copies of the Phase 1 discovery scouts — this skill is installed in
the target project and cannot read the plugin's `references/discovery-checklist.md`.
Spawn each as an Agent/Task scout against the current codebase.

### Scout 1.2 — Architecture

```
You are a codebase architect. Run `tldr tree . --depth 3`, `tldr arch .`, and
`tldr structure . --lang <lang>`, then identify the project's architectural
layers.

Return JSON ONLY:
{
  "scout_id": "1.2",
  "status": "ok" | "no_evidence",
  "summary": "<=200 word prose summary",
  "structured": {
    "layers": [{"name": "<layer>", "dir": "<path>", "deps": ["<other layer>"]}],
    "boundary_table": [{"from": "<layer>", "may_call": [...], "must_not_call": [...]}]
  },
  "evidence_files": ["<paths examined>"]
}
```

### Scout 1.3 — Coding Patterns

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

### Scout 1.5 — Git + CI

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

### Scout 1.6 — Unwritten Rules

```
Compare 3+ files of the same "type" in each detected layer. Find patterns that
are CONSISTENT across all of them — these are unwritten invariants. Also find
patterns NEVER violated.

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

### Scout 1.8 — Data Models

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

### Scout 1.9 — Critical Paths

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

### Scout 1.10 — External Services

```
Grep for external-service SDK imports (stripe, aws-sdk, redis, kafka, postgres,
elasticsearch, openai, twilio, sendgrid, etc.). Read env var config
(.env.example, config/). Look for timeout / retry / circuit-breaker patterns in
calling code.

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

### Per-Layer Spec Scout

```
Read 2-3 representative files in <layer.dir> (the layer whose spec is checked).

Return JSON ONLY:
{
  "layer_name": "...",
  "template_skeleton": "<10-15 line code skeleton>",
  "allowed_imports": [...],
  "forbidden_imports": [...],
  "example_file_path": "..."
}
```

## What This Skill Does NOT Do

- Does not edit any artifact — it only flags (`mark_stale`) and reports.
- Does not refresh — that is `/espalier-prune`.
- Does not run on an idle repo — `doctor_due()` is activity-gated.
