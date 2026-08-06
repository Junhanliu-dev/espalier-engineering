# Migrating v0.16.0 → v0.17.0

v0.17.0 is **Release B-team of the multi-dev maintenance plan**: the weekly gardener rota, the tracked single-line `espalier/.doctor-stamp`, and conventions file-per-key under `espalier/conventions/`. Everything rides pure-copy files — this is the smallest migration in the chain.

## What the migration does

Run `/espalier-migrate` (recommended) or the script directly:

```bash
bash <plugin>/scripts/migrate-v0.16.0-to-v0.17.0.sh --dry-run   # preview
bash <plugin>/scripts/migrate-v0.16.0-to-v0.17.0.sh --yes       # apply
```

- **Pure-copy refresh** (backup-on-diff → `<file>.pre-v0.17.bak`): `espalier/pipeline.md`, the `espalier` / `espalier-fix` / `espalier-prune` / `espalier-doctor` SKILL files, and `espalier/hooks/drift-helpers.sh` (`doctor_due` v2 with clean/dirty shared-stamp semantics + skew rejection, `doctor_stamp_shared`, `conv_slug`, the per-key `append_convention`).
- **No config change, no `.gitattributes` change, no data migration.** `espalier/conventions/` and `espalier/.doctor-stamp` appear on first write; the legacy `.conventions.tsv` is read forever and written never — nothing is rewritten, nothing is converted.
- **Run-time safety assert:** the migration refuses to proceed if a hand-added `.gitignore` rule matches `espalier/.doctor-stamp` — the shared stamp must be tracked.

## What changes day-to-day

- **The gardener rota.** One rotating dev per cadence interval runs the ~15-minute loop: temporary worktree of the canonical branch → `/espalier-doctor` → `/espalier-prune` over the flagged files → if the prune cleared everything, re-run the doctor so the stamp says `clean` → one `docs: weekly espalier maintenance` PR (stamp commit + refresh commits). CODEOWNERS routes any rules-touching part to the rule owner.
- **Everyone else says "Proceed".** Both lanes' Stage 0 pre-flight now defaults to Proceed with a rota pointer; "Handle now" is the default only when one of *your own* flags is critical/expired.
- **The shared stamp.** `doctor_due()` is satisfied team-wide only by a fresh `clean` stamp. A `dirty:N` stamp satisfies only the clone that wrote it. Two stamps colliding (a rota mix-up) resolve as one line vs one line: keep the newer (or either `clean`). Never add a `.gitattributes` union entry for it.
- **Per-key conventions.** New observations and decisions land in `espalier/conventions/k-<key>.tsv`. Different keys can never conflict. A same-key double decision conflicts in that one small file — that conflict *is* the promotion-race detection; pick the winning decision. Same-key append collisions (against another append **or** against a status flip — both conflict on current git, measured in the shipped two-clone sims): **keep both lines**; `conv_fold` dedupes observations at read time.
- **Old branches stay honored.** Pre-v0.17 branches keep appending/flipping the legacy `.conventions.tsv`; `conv_fold` folds it forever, with the rule that a per-key decision beats a legacy one.

## Compatibility

- Squash/rebase/merge all carry both shared facts — they are file contents, not commit-message conventions.
- The shelved event-log design (`docs/multi-dev-maintenance-implementation-plan.md` §5.0) remains the escalation path with measurable un-shelve triggers.
