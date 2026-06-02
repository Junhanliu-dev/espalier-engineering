# Migrating from v0.5.x to v0.6.0 (Stage 1 Grilling)

If your project has an `espalier/` directory bootstrapped with Espalier v0.5.x, this guide upgrades it to v0.6.0 — Stage 1 grilling. The upgrade is non-breaking and mechanical (one script); this doc tells you what changes and what to verify.

## TL;DR

```text
# 1. Update the plugin
/plugin update espalier-engineering

# 2. From inside Claude Code, in your target project:
/espalier-migrate
```

`/espalier-migrate` auto-detects your install version. A v0.5.x install needs only the v0.5→v0.6 step. (An older install gets the full chain — up to v0.1→v0.2→v0.4→v0.5→v0.5.3→v0.6 — applied in order.) It shows a dry-run preview, asks before applying, and runs verification.

To run the script directly instead:

```bash
# from the target project root
bash <plugin>/scripts/migrate-v0.5-to-v0.6.sh --dry-run   # preview
bash <plugin>/scripts/migrate-v0.5-to-v0.6.sh             # apply (prompts)
```

## What v0.6.0 adds

v0.6.0 interrogates the Stage 1 input — the requirement (feat lane) or the bug diagnosis (fix lane) — before any code is written. An under-specified input that passes Stage 1 is otherwise trusted by every later stage with no gate auditing it. Everything is additive and interactive-only; existing behavior is unchanged for unattended (no-TTY) runs.

| New | What it is |
|---|---|
| `espalier-grill` skill | Adaptive sequential interrogation at Stage 1. Scores ambiguity *signals* in the input, maps the count to a depth tier, and resolves each gap into `requirements.md`. Two modes: `spec` (`/espalier`) and `diagnosis` (`/espalier-fix`). Invoked *by* Stage 1 — never a user-facing slash command. |
| Stage 1 wiring | `/espalier`, `/espalier-fix`, and `espalier-requirements` now call the grill. On by default; per-invocation opt-out via `--no-grill`. Auto-skipped on a non-interactive run (verdict `SKIPPED: non-interactive`) so an unattended pipeline never hangs. |
| Dated change folders | New change folders use `{slug}` = `YYYY-MM-DD-{kebab}` (UTC creation date as a prefix) so `changes/{feat,fix,refactor}/` lists chronologically. Fix-lane collision/resume matches by the `{kebab}` tail; reverse-lookup is unaffected (it derives slug from the folder basename). |

## What the migration does

`scripts/migrate-v0.5-to-v0.6.sh` (invoked by `/espalier-migrate`) runs:

1. **Backup-on-diff** — for each pure-copy pipeline file (`pipeline.md`, `espalier`, `espalier-fix`, `espalier-requirements`), if your live copy differs from the v0.6 template, it is copied aside to `<file>.pre-v0.6.bak` *before* anything is overwritten, so a customisation is recoverable.
2. **`bootstrap-espalier.sh --force`** — creates `espalier/skills/espalier-grill/`, copies the new `SKILL.md`, refreshes the four changed pipeline files, and symlinks `.claude/skills/espalier-grill`.
3. **Verification** — checks the grill skill is present and wired, the `--no-grill` flag is parseable in both lanes, and the symlink resolves. Reports `X passed, Y failed`.

Idempotent: re-running detects an already-v0.6 install (grill skill present + Stage 1 wired) and no-ops.

## What it does NOT touch

- `espalier/rules/*`, `espalier/wiki/*`, `espalier/changes/*`, or any LLM-substituted file (`harness-coder.md`, `harness-reviewer.md`, `pre-push-gate.sh`, `espalier-review.md`) — none changed in v0.6.
- In-flight feat or fix work. v0.6 only affects *new* pipeline invocations; existing undated change folders are left as-is.

## After migrating

- Run `/espalier` on a new feat — Stage 1 grills the requirement before coding.
- Skip the grill for one invocation with `--no-grill`.
- If a backup was written, diff it against the live file to re-apply any customisation:
  ```bash
  diff espalier/<file>.pre-v0.6.bak espalier/<file>
  ```
