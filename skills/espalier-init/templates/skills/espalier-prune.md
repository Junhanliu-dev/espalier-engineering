---
name: espalier-prune
description: Refresh stale Espalier artifacts (rules, wiki, layer specs, hooks) by re-running discovery scouts and applying a gated, per-file diff
---

# Espalier Prune

The ONLY component that edits an Espalier doc. Interactive, per-file, always
gated — it never overwrites a doc without an explicit user accept.

## When to Use

- "/espalier-prune <path>" — refresh one flagged artifact
- "/espalier-prune --all-stale" — refresh every file in the drift sidecar
- Surfaced by the Stage 0 pre-flight when a doc is flagged stale

## Trigger

```
/espalier-prune <path>        # refresh a single artifact
/espalier-prune --all-stale   # refresh every flagged artifact
```

With `--all-stale`, the file list comes from the drift sidecar:

```bash
. espalier/hooks/drift-helpers.sh
stale_files          # one repo-relative path per line (empty if no drift)
```

## Per-File Refresh Protocol

Each step is a real tool action (scout spawn, Read, diff, AskUserQuestion) —
NOT a bash script. For each file:

1. **Look up the scout(s)** for the file (Scout Mapping below).
2. **Spawn the scout(s)** — prompts are embedded in this skill (Embedded Scout
   Prompts below). The scout runs against the CURRENT codebase. For a file with
   two scouts (`coding-standards.md` ← 1.3 + 1.6), spawn both and merge their
   outputs into ONE proposed file before diffing.
3. **Two-way diff:** current file vs the proposed scout output. Two-way, not
   three-way — the init template is full of `{placeholders}` and is useless as
   a diff base.
4. **If the diff is empty or immaterial** (a teammate already refreshed the
   file): `clear_stale <file>`, report "already current", move on — no prompt.
   Under the per-clone sidecar a teammate's fix leaves a phantom row on your
   clone; this retires it instead of nagging forever.
5. **Else render the unified diff** and gate by file class with
   `AskUserQuestion`. Classify with `classify_file <path>` from
   `drift-helpers.sh`:

   | File class | Options | Default |
   |------------|---------|---------|
   | Wiki  | apply / review / skip | apply |
   | Rules | apply / keep-old / show-full-diff / edit | (none) |
   | Specs (layer_spec) | apply / keep-old / edit | (none) |
   | Hooks | apply / keep-old / edit + dry-run validate | (none) |

6. **On apply:** overwrite the file, then `clear_stale <file>`.
7. **On skip / keep-old:** leave the sidecar row — it re-surfaces at the next
   Stage 0 pre-flight.

After all files, report a summary: applied / already-current / kept-old /
skipped. Then suggest a commit:

> docs: refresh stale espalier artifacts

Commit it BEFORE resuming any pipeline, so the refresh is its own commit and is
never bundled into a feature commit.

## Unattended Invocation

```bash
. espalier/hooks/drift-helpers.sh
[ "$(detect_run_mode)" = "unattended" ] && echo unattended
```

If invoked unattended (CI, loop, non-tty) with `--all-stale`: do NOT prompt.
Write the proposed diffs to `espalier/.drift-report.md` and exit, leaving every
sidecar row in place. Refresh is never silent.

## Scout Mapping

| Artifact | Scout(s) |
|----------|----------|
| `rules/engineering-structure.md` | 1.2 |
| `rules/coding-standards.md` | 1.3 + 1.6 (merge before diff) |
| `rules/development-process.md` | 1.5 |
| `wiki/architecture.md` | 1.2 |
| `wiki/data-models.md` | 1.8 |
| `wiki/critical-paths.md` | 1.9 |
| `wiki/external-services.md` | 1.10 |
| `skills/espalier-coding/specs/{layer}.md` | per-layer spec scout |
| `hooks/check-layer-boundaries.sh` | 1.2 → regenerate the `case` block |
| `hooks/pre-push-gate.sh` | 1.5 → re-substitute build/lint/test commands |

A hook is not a prose doc. For `check-layer-boundaries.sh` regenerate the layer
`case` block from scout 1.2's `layers`; for `pre-push-gate.sh` re-substitute the
`{build_command}` / `{lint_command}` / `{test_command}` placeholders from scout
1.5's `ci_checks`. Always dry-run a refreshed hook (`bash -n <hook>`) before the
apply gate.

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
Read 2-3 representative files in <layer.dir> (the layer whose spec is stale).

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

- Does not re-run a full `/espalier-init`. It refreshes only flagged files.
- Does not promote conventions. Promotion is a deliberate rule edit handled at
  the Stage 0 pre-flight (see the `espalier` skill's Convention Promotion
  section). A scout re-derives a rule from a code base that is now a MIX of old
  and new patterns; it reports the mix, it cannot make the promote/reject call.
- Never edits a doc without an explicit user accept (attended), or at all
  (unattended — it only writes a report).
