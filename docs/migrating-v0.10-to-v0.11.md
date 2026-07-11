# Migrating from v0.10.0 to v0.11.0 (Hook Exit-Code Contract)

## TL;DR

```bash
# 1. Update the plugin
/plugin update espalier-engineering

# 2. From inside Claude Code, in your target project:
/espalier-migrate
```

Or run the script directly:

```bash
# from the target project root
bash <plugin>/scripts/migrate-v0.10.0-to-v0.11.0.sh --dry-run   # preview
bash <plugin>/scripts/migrate-v0.10.0-to-v0.11.0.sh --yes
```

## What v0.11.0 changes — and why

A correctness audit of v0.10.0 found the release's most load-bearing assumption
was wrong: **Claude Code PreToolUse/PostToolUse hooks block only on exit
code 2, with the message on stderr.** Exit 1 + stdout — the convention every
gate script used, borrowed from git-hook semantics — is a silent no-op in hook
context. In other words, the push gate never actually blocked a push, and the
layer-boundary check never actually surfaced a violation.

v0.11.0 fixes the contract end-to-end:

- **`pre-push-gate.sh`** — every blocking path exits 2 with the reason on
  stderr; warnings also print to stderr. The secret scan now runs even when no
  pipeline change is in flight (a between-pipelines manual push used to skip
  it). A corrupt or hand-edited `pipeline-state.md` (missing `Current Stage:`,
  or a Stage-4 PASSED row with no review certificate) fails **closed** instead
  of silently skipping the gate.
- **`pre-push-gate-wrapper.sh`** — fails **closed** (exit 2) when python is
  missing instead of silently allowing every push; matches `git -C /path push`,
  multi-line commands, and pushes after `&&`, while still ignoring quoted
  mentions like `echo "git push"`. `ESPALIER_SKIP_GATE=1` is the documented
  one-shot bypass.
- **`check-layer-boundaries.sh`** — violations exit 2 with the message on
  stderr (PostToolUse contract).
- **Verdict gates (Stage 4/6, both lanes)** — the orchestrator now reads the
  verdict **word**, not just `p0=`: `FAIL` with only P1s open loops the panel,
  and `ESCALATION_REQUIRED` triggers the escalation protocol instead of
  advancing as a pass. Advancement requires PASS/PASS_WITH_FIXES with `p0=0`
  **and** `p1=0`.
- **Agents** — `harness-reviewer` / `harness-security` gain the Write tool,
  contractually restricted to their own record file (they previously had to
  "Write (OVERWRITE)" records with no Write tool).

## What the migration script edits

`migrate-v0.10.0-to-v0.11.0.sh`, in order:

1. Rebuilds `espalier/hooks/pre-push-gate.sh` from the v0.11.0 template,
   **preserving the three command bodies substituted at init**
   (`run_build` / `run_lint` / `run_tests` — single commands or multi-line
   blocks). Backup: `pre-push-gate.sh.pre-v0.11.bak`.
2. Overwrites `pre-push-gate-wrapper.sh` and `post-edit-wrapper.sh` from the
   templates (pure copies; `.pre-v0.11.bak` backups).
3. Patches `check-layer-boundaries.sh` via anchored sed: `exit 1` → `exit 2`,
   the `LAYER VIOLATION` echo gains `>&2`. An unrecognizable shape is left
   alone and recorded (see below).
4. Appends `, Write` to the reviewer/security agents' `tools:` frontmatter
   lines (an inherit-mode install has no `tools:` line — logged and skipped,
   never treated as a failure) and fixes the stale "you have no Write/Edit"
   sentence.
5. Overwrites `espalier/pipeline.md` and the eight pure-copy pipeline skills
   (`espalier`, `espalier-fix`, `espalier-requirements`, `espalier-grill`,
   `espalier-prune`, `espalier-doctor`, `espalier-ask`, `espalier-audit`) from
   the templates, with `.pre-v0.11.bak` backups.
6. Refreshes `espalier-review` / `espalier-security` SKILL.md from the
   templates, re-substituting `{project}` with the name recovered from your
   installed files.
7. Runs a verification block (exit 2 counts, wrapper fail-closed branch, agent
   tools lines, verdict-gate line, no `{project}` literals) and exits non-zero
   if any check fails.

## What a customised install must port by hand

If your `pre-push-gate.sh` was customised at init past the template shape
(e.g. a Docker-first gate running each suite in its own container), the script
**leaves it untouched**, records
`v0.11.0-gate: customised, manual port needed` in
`espalier/.migrations-skipped` (so `/espalier-migrate` reports it once instead
of re-proposing forever), and prints the contract to port yourself:

- every blocking path must `exit 2` with the reason on **stderr** —
  Claude Code PreToolUse semantics; `exit 1` does NOT block;
- warnings also print to stderr (stdout is invisible in hook context);
- the secret scan must run even when no pipeline change is in flight.

The same skip-marker pattern applies to an unrecognizable
`check-layer-boundaries.sh` (`v0.11.0-layer-hook: …`).

## Rollback

Every file the script rewrites is backed up next to itself as
`<file>.pre-v0.11.bak`. To roll back, copy the backups over the live files:

```bash
for f in $(find espalier -name '*.pre-v0.11.bak'); do
  cp "$f" "${f%.pre-v0.11.bak}"
done
```

Delete the backups once you are satisfied.

## Non-breaking

No stage was added or removed; no state-file schema changed. Statuses
`ESCALATED` / `ESCALATED_LATE` / `FILED` — previously consumed but never
written — are now written at the paths that always described them, and resume
is status-driven (`- Status: IN_PROGRESS`) instead of stage-numbered.
