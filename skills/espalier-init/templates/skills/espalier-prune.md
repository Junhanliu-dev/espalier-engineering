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
2. **Spawn the scout(s)** — read the prompts from `espalier/.scout-prompts.md`
   (Scout Prompts (shipped file) below). The scout runs against the CURRENT codebase. For a file with
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
[ "$(interactivity_mode)" = "unattended" ] && echo unattended
```

Only an EXPLICIT unattended signal counts (`CI`, `ESPALIER_UNATTENDED`,
`ESPALIER_LOOP`, `ESPALIER_HEADLESS`) — never a bash TTY test, which reads
"no TTY" inside every interactive Claude Code session and would demote every
attended `--all-stale` run to report-only. If you (the orchestrator) can call
`AskUserQuestion`, you are interactive: gate each file normally.

If genuinely unattended with `--all-stale`: do NOT prompt. Write the proposed
diffs to `espalier/.drift-report.md` and exit, leaving every sidecar row in
place. Refresh is never silent.

## Scout Mapping

| Artifact | Scout(s) |
|----------|----------|
| `rules/engineering-structure.md` | 1.2 |
| `rules/coding-standards.md` | 1.3 + 1.6 (merge before diff) |
| `rules/development-process.md` | 1.5 |
| `rules/security-standards.md` | 1.11 → discovered sections ONLY (see below) |
| `rules/production-standards.md` | 1.3 + 1.10 + 1.8 → `{discovered}` cells ONLY (merge before diff) |
| `wiki/architecture.md` | 1.2 |
| `wiki/data-models.md` | 1.8 |
| `wiki/critical-paths.md` | 1.9 |
| `wiki/external-services.md` | 1.10 |
| `skills/espalier-coding/specs/{layer}.md` | per-layer spec scout |
| `hooks/check-layer-boundaries.sh` | 1.2 → regenerate the `case` block |
| `hooks/pre-push-gate.sh` | 1.5 → re-substitute build/lint/test commands |

The two always-loaded standards rules are MIXED files — universal seed text
plus discovered cells. A refresh regenerates ONLY the discovered parts:
`security-standards.md` = the Trust Boundary bullets, the per-axis
`{discovered}` taxonomy column, and Project-Specific Security Conventions
(from scout 1.11); `production-standards.md` = the `{discovered}` mechanism
cells and Project-Specific Production Conventions (from 1.3's
logging/error-handling/validation, 1.10's timeout_retry_patterns, 1.8's
migration_pattern). The universal taxonomy, required controls, seeds, and
severity tiers are fixed text — never rewritten by a scout; the two-way diff
must show them unchanged.

A hook is not a prose doc. For `check-layer-boundaries.sh` regenerate the layer
`case` block from scout 1.2's `layers`; for `pre-push-gate.sh` re-substitute the
`{build_command}` / `{lint_command}` / `{test_command}` placeholders from scout
1.5's `ci_checks`. Always dry-run a refreshed hook (`bash -n <hook>`) before the
apply gate.

## Scout Prompts (shipped file)

Read the prompts from `espalier/.scout-prompts.md` — they are NOT embedded here. The file is copied into this project at init. Spawn the scout(s)
mapped to the artifact under refresh (Scout Mapping above); run each as an
Agent/Task scout against the current codebase. Keeping the prompts in a single
shipped file means `/espalier-prune` and `/espalier-doctor` can never drift apart.

For a file with two scouts (`coding-standards.md` ← 1.3 + 1.6), spawn both and
merge their outputs into ONE proposed file before diffing. For a hook, regenerate
the scripted block from the scout's structured output (see Scout Mapping notes),
never prose.

## What This Skill Does NOT Do

- Does not re-run a full `/espalier-init`. It refreshes only flagged files.
- Does not promote conventions. Promotion is a deliberate rule edit handled at
  the Stage 0 pre-flight (see the `espalier` skill's Convention Promotion
  section). A scout re-derives a rule from a code base that is now a MIX of old
  and new patterns; it reports the mix, it cannot make the promote/reject call.
- Never edits a doc without an explicit user accept (attended), or at all
  (unattended — it only writes a report).
