# Migrating from v0.6.x to v0.7.0 (Read-Only Ask Lane)

If your project has an `espalier/` directory bootstrapped with Espalier v0.6.x, this guide upgrades it to v0.7.0 — the read-only `/espalier-ask` lane. The upgrade is non-breaking and mechanical (one script); this doc tells you what changes and what to verify.

## TL;DR

```text
# 1. Update the plugin
/plugin update espalier-engineering

# 2. From inside Claude Code, in your target project:
/espalier-migrate
```

`/espalier-migrate` auto-detects your install version. A v0.6.x install needs only the v0.6→v0.7 step. (An older install gets the full chain — up to v0.1→v0.2→v0.4→v0.5→v0.5.3→v0.6→v0.7 — applied in order.) It shows a dry-run preview, asks before applying, and runs verification.

To run the script directly instead:

```bash
# from the target project root
bash <plugin>/scripts/migrate-v0.6-to-v0.7.sh --dry-run   # preview
bash <plugin>/scripts/migrate-v0.6-to-v0.7.sh             # apply (prompts)
```

## What v0.7.0 adds

v0.7.0 adds a read-only question-answering lane. It does not change any pipeline stage, gate, or sub-agent — `/espalier` and `/espalier-fix` behave exactly as before.

| New | What it is |
|---|---|
| `espalier-ask` skill | `/espalier-ask <question>` answers "how / where / why / what-changed" questions. It classifies the question, reads the `espalier/` docs that bear on it (wiki for *how/where*, `changes/*/requirements.md` + `review-record.md` for *why*), **verifies every doc claim against the cited code** before asserting it, and falls back to a codebase search when the docs are silent. Every claim is sourced (doc path and/or `file:line`). |
| Drift byproduct | A wiki the skill reads that contradicts the code is flagged via the existing `mark_stale` drift sidecar (reason `ask-verify: …`) and you're pointed at `/espalier-prune`. Notify-only — it never edits the doc. |
| Gap byproduct | A question the docs cannot answer is appended to `espalier/.ask-gaps.tsv` (git-**tracked**, unlike the per-clone drift sidecars) as a backlog of what the wiki should cover next. |

The skill is strictly read-only on your Espalier artifacts: it never edits a wiki/rule/spec and never opens a `changes/` folder. Its only writes are the two append-only sidecar rows above.

## What the migration does

`scripts/migrate-v0.6-to-v0.7.sh` (invoked by `/espalier-migrate`) runs:

1. **Backup-on-diff** — `bootstrap --force` re-copies *every* pure-copy pipeline file, even the ones v0.7 did not change. For each (`pipeline.md`, `espalier`, `espalier-fix`, `espalier-requirements`, `espalier-grill`, `espalier-prune`, `espalier-doctor`), if your live copy differs from the v0.7 template it is copied aside to `<file>.pre-v0.7.bak` *before* anything is overwritten, so a customisation is recoverable.
2. **`bootstrap-espalier.sh --force`** — creates `espalier/skills/espalier-ask/`, copies the new `SKILL.md`, and symlinks `.claude/skills/espalier-ask`.
3. **CLAUDE.md + agent.md patch** — inserts a `/espalier-ask` line into the `## Espalier` block of `CLAUDE.md` and an `Ask` row into the config-index table of `espalier/agent.md`. (Bootstrap's `CLAUDE.md` writer is append-once and skips an existing section, and it never touches the per-project `agent.md`, so the migration does both directly.)
4. **Verification** — checks the skill is present, the symlink resolves, the skill name parity holds, and that `CLAUDE.md`/`agent.md` mention `/espalier-ask` (the last two are warn-only). Reports `X passed, Y failed`.

Idempotent: re-running detects an already-v0.7 install (`espalier-ask` skill present) and no-ops. The two file patches are also individually guarded — they skip if `/espalier-ask` is already mentioned.

## What it does NOT touch

- `espalier/rules/*`, `espalier/wiki/*`, `espalier/changes/*`, or any LLM-substituted hook — none changed in v0.7.
- Any pipeline behaviour. `/espalier` and `/espalier-fix` are unchanged; existing in-flight work is unaffected.

## After migrating

- Try it: `/espalier-ask how does <some feature> work` — it answers from your docs first, verified against the code.
- If the skill flags a stale doc while answering, refresh it with `/espalier-prune <path>`.
- The gap log `espalier/.ask-gaps.tsv` is tracked — commit it with your next change; it accrues the questions your wiki should grow to answer.
- If a backup was written, diff it against the live file to re-apply any customisation:
  ```bash
  diff espalier/<file>.pre-v0.7.bak espalier/<file>
  ```
