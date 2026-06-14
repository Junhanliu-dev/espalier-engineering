# Migrating from v0.7.x to v0.8.0 (Requirements Approval Gate)

If your project has an `espalier/` directory bootstrapped with Espalier v0.7.x, this guide upgrades it to v0.8.0 — the requirements approval gate. The upgrade is non-breaking and mechanical (one script); this doc tells you what changes and what to verify.

## TL;DR

```text
# 1. Update the plugin
/plugin update espalier-engineering

# 2. From inside Claude Code, in your target project:
/espalier-migrate
```

`/espalier-migrate` auto-detects your install version. A v0.7.x install needs only the v0.7→v0.8 step. (An older install gets the full chain — up to v0.1→v0.2→v0.4→v0.5→v0.5.3→v0.6→v0.7→v0.8 — applied in order.) It shows a dry-run preview, asks before applying, and runs verification.

To run the script directly instead:

```bash
# from the target project root
bash <plugin>/scripts/migrate-v0.7-to-v0.8.sh --dry-run   # preview
bash <plugin>/scripts/migrate-v0.7-to-v0.8.sh             # apply (prompts)
```

## What v0.8.0 changes

Before v0.8, both pipelines chained Stage 1 (requirements) → Stage 2 (requirements review) → Stage 3 (coding) automatically. The moment the requirement doc existed, coding began — you never got a chance to sign off on the spec.

v0.8 adds a **blocking requirements approval gate**. After the requirement is written and reviewed, the pipeline STOPS and asks for explicit sign-off before any code is written.

| Lane | Where the gate sits |
|---|---|
| `/espalier` (full pipeline) | Between Stage 2 (requirements review) and Stage 3 (coding). A Stage 2 PASS alone no longer authorizes coding. |
| `/espalier-fix` (5-stage fix lane) | After Stage 1 (bug requirements + diagnosis grill), before Stage 3. Runs *after* the Stage 1 escalation gate — only an in-lane fix reaches the approval gate. |

At the gate the orchestrator presents the final `requirements.md` (goal, acceptance criteria, what the Stage 1 grill resolved or scoped out) and asks via `AskUserQuestion`:

- **Approve** — proceed to coding.
- **Edit** — say what to change; it revises `requirements.md`, re-runs the review gate, and re-asks.
- **Abort** — stop; the requirement is left as a draft (`Status: ABORTED`).

**Non-interactive runs auto-approve.** On a no-TTY run (the same condition that auto-skips the Stage 1 grill) the gate cannot prompt — it records `requirements auto-approved (non-interactive)` in the Stage History and proceeds, so unattended pipelines never hang. Interactive runs ALWAYS prompt.

## What the migration does

`scripts/migrate-v0.7-to-v0.8.sh` (invoked by `/espalier-migrate`) runs:

1. **Backup-on-diff** — `bootstrap --force` re-copies *every* pure-copy pipeline file, even the ones v0.8 did not change. For the three files v0.8 *does* change (`pipeline.md`, `espalier`, `espalier-fix`), if your live copy differs from the v0.8 template it is copied aside to `<file>.pre-v0.8.bak` *before* anything is overwritten, so a customisation is recoverable.
2. **`bootstrap-espalier.sh --force`** — refreshes the three changed pure-copy templates with the approval-gate versions.
3. **Verification** — checks the approval-gate text landed in the espalier skill and espalier-fix skill, that the Stage 2 → Stage 3 carve-out is present, and that `pipeline.md` carries the blocking Stage 2 checkpoint. Reports `X passed, Y failed`.

No new skill, no new pipeline stage. Idempotent: re-running detects an already-v0.8 install (approval-gate text present in `espalier/skills/espalier/SKILL.md`) and no-ops.

## What it does NOT touch

- `espalier/rules/*`, `espalier/wiki/*`, `espalier/changes/*`, or any LLM-substituted file (`harness-coder.md`, `harness-reviewer.md`, `pre-push-gate.sh`, `espalier-review.md`) — none changed in v0.8.
- Any in-flight feat or fix. The gate only affects new pipeline invocations.

## After migrating

- Try it: `/espalier feat: <some small feature>` — after Stage 2 the pipeline pauses for your Approve / Edit / Abort before coding begins.
- If a backup was written, diff it against the live file to re-apply any customisation:
  ```bash
  diff espalier/<file>.pre-v0.8.bak espalier/<file>
  ```
