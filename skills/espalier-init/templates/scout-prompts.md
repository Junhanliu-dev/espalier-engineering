# Espalier Discovery Scout Prompts (shipped)

Canonical, target-side copies of the Phase 1 discovery scouts. `/espalier-prune`
and `/espalier-doctor` both read THIS file (they ship into the target project and
cannot read the plugin's `references/discovery-checklist.md`) — the single source
of truth for re-scouting an artifact. Spawn the scout(s) mapped to the artifact
under refresh; run each as an Agent/Task scout against the current codebase.

> Sync note: this file mirrors the scout blocks in the plugin's
> `references/discovery-checklist.md`. When a scout's JSON shape changes, edit
> BOTH. Bootstrap copies this file to `espalier/.scout-prompts.md` in the target.

## Scout 1.2 — Architecture

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

## Scout 1.3 — Coding Patterns

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

## Scout 1.5 — Git + CI + deploy

```
Read git log + CI configs (.github/workflows/, Jenkinsfile, Makefile, justfile).
Also look for deploy configuration: deploy workflows/jobs, Procfile, Dockerfile +
compose/k8s manifests, fly.toml, vercel.json, serverless.yml — and any health/
readiness endpoint the app exposes (grep routes for /health, /healthz, /ready,
/ping). Deploy discovery is OPTIONAL — when the repo has no deploy config, set
"deploy": null (do NOT invent one).

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
    },
    "deploy": {
      "mechanism": "<e.g. 'GitHub Actions deploy.yml on main' | 'fly deploy'>",
      "command": "<exact command, or 'automatic on merge'>",
      "health_check": "<URL path or command, e.g. 'GET /healthz'>",
      "environment": "<staging|production|both>"
    }
  },
  "evidence_files": [...]
}
```

## Scout 1.6 — Unwritten Rules

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

## Scout 1.8 — Data Models

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

## Scout 1.9 — Critical Paths

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

## Scout 1.10 — External Services

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

## Per-Layer Spec Scout

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
