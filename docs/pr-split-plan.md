# v0.29.0 — the PR split: code PR / espalier PR + in-pipeline doc sweep

Status: **plan, not implemented.**

**Not a new lane.** No new command, no new state machine. This changes shared
stages inside the existing pipeline:

| Lane | Stage 7 split | Doc sweep |
|------|---------------|-----------|
| feat (`/espalier`) | yes | yes |
| fix (`/espalier-fix`) | yes — Stages 3–7 are shared (`espalier-fix.md:227`) | yes |
| map / run (`/espalier-maprun`) | no — unchanged | no |

### Why the sweep sits in Stage 7, not 8.5

The fix lane is 7 stages (0–7) and skips Stages 8, 9 and 10
(`espalier-fix.md:31-36`) — there is no 8.5 to hook, so a sweep placed there
would silently never run for a fix. The ask was explicitly "feat/fix", so the
sweep sits at the **end of Stage 7**, the last shared stage.

Accepted cost: at 8.5 the sweep would run after CI passes and refresh docs only
for verified code; at Stage 7 it runs before CI, so a refresh can describe code
that then fails. Visible and cheap — PR2 is a separate PR a human merges, and
the fix lane defers to repo CI regardless. The alternative was a silent,
permanent gap.

## What changes

1. A run ends in **two sibling PRs**, both based on `main`: a code PR
   (everything outside `espalier/`) and an espalier PR (all of `espalier/**`).
2. **Stage 7 opens both** with `gh`. The single-change lane has never created a
   PR (only `maprun-pr.sh:230,283` does).
3. **Stage 7 gains a doc sweep**: it sweeps this change's diff against
   `espalier/wiki/**` + `espalier/rules/**` and commits refreshes onto the
   espalier branch. Stage 8.5's notify-only sidecar table is unchanged.

Locked: path split · Stage 7 opens both · **sibling PRs** · every change gets an
espalier PR · branch `{type}/{slug}-espalier` · Stage 10 completes with both
open · sweep auto-commits, additive-only, wiki+rules · `harness-reviewer` +
new `wiki-sweep` mode · all change types · fixture eval + migration e2e.

## Topology

```
Base-Ref ──┬── {type}/{slug} ──────●──●       PR1  base: main  diff: code only
           └── {type}/{slug}-espalier ──●──●  PR2  base: main  diff: espalier/** only
```

B is cut from `Base-Ref` and carries **no code commits**. Both PRs target
`main` and merge in any order. B is named `{type}/{slug}-espalier` so it rides
the project's existing branch prefix — `pipeline.md:96` gates on "branch name
matches convention", and a dedicated `espalier/*` prefix would need an
exemption there.

Merge ordering is **advisory**: PR2's body carries `merge after #N`. Nothing
enforces it. Worst case, `main`'s wiki describes a change whose code has not
landed, for one review cycle — and `/espalier-doctor` flags that on its next
scan, because it re-scouts against the current codebase.

## Why siblings and not a stack (probe evidence, 2026-09-18)

A base-pointer stack — PR2 based on the code branch — was designed first and
**probed on a throwaway repo before any code was written**. It failed:

```
squash-merge PR1 --delete-branch
  timeline: base_ref_deleted → closed  (same second)
  PR2: base=feat/probe  state=CLOSED  mergeable=CONFLICTING
  gh pr edit --base main → "Cannot change the base branch of a closed pull request"
  gh pr reopen           → "Could not open the pull request"
```

GitHub does not retarget a child PR when its base branch is deleted — it
**closes** it, irrecoverably. The base of a closed PR cannot be changed and the
PR cannot be reopened without its base. The branch survives, so no work is lost,
but the PR, its review and its comments are gone.

Merging without deleting, then retargeting while still open, does work:

```
squash-merge PR3 (branch kept) → PR4 base=feat/probe2 OPEN MERGEABLE
gh pr edit --base main         → PR4 base=main OPEN MERGEABLE, espalier/-only diff
merge PR4 --squash             → MERGED; main has two clean squash commits
```

But that makes the stack depend on a human doing a retarget between two merges,
destroyed by the "Delete branch" button GitHub offers on the merge screen — and
destroyed automatically, every time, in any repo with `deleteBranchOnMerge:
true`, while the pipeline has already exited at Stage 10 and nobody is watching.

Two further facts settle it. The recovery for a destroyed stacked PR is to open
a new PR from the surviving branch, and its base must be `main` — the recovery
path *is* the sibling topology. And `docs/maprun-stacked-pr-plan.md` already
records a stacked design rejected for the run lane, finding #1 being exactly
this merge-strategy coupling. Siblings cost only enforced ordering.

The probe also confirmed the property siblings depend on: a branch cut from an
old base carrying only `espalier/` commits merges cleanly into a `main` that has
already moved.

## Two blockers found in the existing code

**B1 — the push gate blocks branch B.** `pre-push-gate.sh:126` fingerprints
`git diff $BASE_REF -- . ':(exclude)espalier/'` against the current checkout and
exits 2 on mismatch. On B that diff is empty, so it can never match. The gate
finds its state file by mtime, not branch name — no escape hatch.

→ Push B **by refspec from the code branch's checkout**
(`git push origin $TYPE/$SLUG-espalier:$TYPE/$SLUG-espalier`, HEAD on the code
branch). The hook then passes for the reason it was written. Same trick as
`maprun-pr.sh:23-25`. **No edit to the gate.** Verified working in the probe.

**B2 — `espalier/` is live working state through Stage 10.** Stages 8–10 keep
writing `ci-result.md`, `doc-patches.md`, `delivery-brief.md`. Commit those onto
B and switch back, and the files leave the tree: the gate finds no active change
and Stage 10 has nothing to assemble.

→ B is a **projection**. The main checkout never leaves the code branch;
`espalier/` stays dirty there; a helper syncs it onto B in a temp worktree at
Stage 7 and at Completion, one-way, so the copies cannot diverge. Smaller than
it sounds: `7-10-delivery.md` already leaves the records uncommitted until
Stage 7.

→ Consequence: `pipeline.md:96`'s "clean working tree" gate becomes "clean
outside `espalier/`". Doc-only — verified `pre-push-gate.sh` has no cleanliness
check.

## Work items

**New `hook-templates/espalier-pr.sh`** — modelled on `maprun-pr.sh` (gh absent
= exit 5 + warning, never blocks, never force-pushes).
`project` (sync+commit via temp worktree) · `push` (both branches by refspec) ·
`open` (two `gh pr create`, both `--base main`, PR2 body carries `merge after
#N`) · `status`. Records a `## Pull Requests` table in `pipeline-state.md`.

**`espalier-stages/7-10-delivery.md`** — Stage 7: code commits stay on A, the
records commit routes through `espalier-pr.sh project`, the checkout never
switches branches. `record_commits` now records code commits only, which makes
the `post-merge-backlink.sh` file-overlap match (`:31-37`) *cleaner* than today;
add a branch column so B's squash can be backlinked too. Stage 10: brief gains
`## Pull Requests` and `## Doc Refresh`, presents both PR links, and marks
COMPLETE with both PRs open — merging stays entirely a human act.

**Stage 7 — the sweep.** Runs after the code commits and **before** the
espalier projection, so its edits ride the same PR2. Order within Stage 7:
code commits → sweep → `espalier-pr.sh project` → `push` → `open`.

It is a new, diff-driven pass, unrelated to `stage85_drift`
(`drift-helpers.sh:796`), which reads the `.drift-state.tsv` staleness sidecar
and stays at 8.5 in the full lane, notify-only, unchanged:
1. fast-skip when the diff touches no source file;
2. one `harness-reviewer` call in `wiki-sweep` mode (diff + wiki + rules) — not
   `/espalier-prune`, which re-derives via discovery scouts and is neither
   diff-scoped nor cheap;
3. commit accepted edits via `espalier-pr.sh project`, one commit per class,
   never folded into the records commit;
4. **deletions are never applied** — routed to `doc-patches.md` for a human
   prune, mirroring prune's "Removed rules" ledger;
5. Stage 8.5's sidecar notify table still runs in the full lane, untouched.

**New `agents/modes/wiki-sweep.md`** — joins `fix-round`, `re-review`,
`simplification`, `stage6-abuse-coverage`, `repo-audit`. Per file: `NO-IMPACT`
or a patch plus a justification citing the diff hunk that evidences it.
Additive only; no claim untraceable to a hunk; silence is a correct answer.

**`rules/development-process.md`** — the `ESPALIER MAINTENANCE COMMITS v1`
anchor currently says the opposite ("routine prune refreshes ride ONE weekly
maintenance PR"). Bump to v2: *drift your change caused rides your change's
espalier PR as its own isolated commit; drift you didn't cause stays on the
weekly gardener lane.* "Never folded into feature commits" survives — PR2 is a
separate PR. Also note: when the sweep writes `espalier/rules/`, PR2 needs a
rule owner (`:37`, CODEOWNERS), so Stage 7 must label PR2's body — the stall
should be visible, not mysterious.

**Also:** `pipeline.md` Stages 7 and 10 (frozen headings untouched; 8.5's
notify-only contract is unchanged); `espalier-fix.md` Stage 7 mirrors the
split and the sweep;
`harness-coder.md` Commit Discipline — code only, never stage `espalier/`;
`bootstrap-espalier.sh` emits the new hook. No new config key. No
`deleteBranchOnMerge` detection — harmless once PR2 targets `main`.

## Migration

`migrate-v0.28.1-to-v0.29.0.sh` + `docs/migrating-v0.28-to-v0.29.md`: install
the hook and the mode, patch the maintenance anchor v1→v2, patch pipeline.md by
heading anchor. A change already at Stage ≥ 7 finishes on the old single-branch
path — notice only, never retro-split a pushed branch. Idempotent.

## Verification

1. **Live forge probe — DONE** (2026-09-18, `Junhanliu-dev/espalier-prstack-probe`).
   Established the stack failure above, the sibling merge property, and the B1
   push-by-refspec mechanic. The repo still exists; the token lacks
   `delete_repo`, so removing it is a manual step.
2. **`eval/prstack/`** in the shape of `eval/review/` — fixtures: a diff that
   plainly invalidates `wiki/architecture.md` (must patch); test-only diff (must
   fast-skip); a diff tempting a rule deletion (must route to `doc-patches.md`,
   commit nothing); a no-impact diff (must return `NO-IMPACT` — silence is the
   pass condition and the easiest to fail).
3. **Migration chain e2e** — worktree at v0.28.1 → old bootstrap → new migrate →
   assert anchor bumped, hook installed, in-flight notice fired.

## Open risks

- Merge ordering is advisory. `main`'s wiki can lead its code by one review
  cycle; doctor flags it on the next scan.
- Two PRs per change doubles forge noise: **every** change gets an espalier PR,
  including records-only ones. Decided deliberately — a conditional split is two
  code paths and two fixture sets instead of one.
- Rule sweep can stall PR2 behind a rule owner (accepted).
- A permanently-dirty `espalier/` surprises anyone running `git status` mid-run
  — mitigate with a Stage 7 message naming what is dirty and why.
- If PR2 is closed and never merged, the wiki/rules half self-heals via
  doctor+prune, but the change records do **not** — they are not scout-derivable,
  and `/espalier-fix` Stage 0 reverse lookup depends on them.
