# v0.20.0 — Slice PRs on the integration branch (one ticket, one reviewable PR)

Design record for giving the run lane per-ticket pull requests **without
changing its merge topology**. Field-derived, from the same production repo
that produced v0.19.0: a 14-ticket Keystone schema map, five tickets merged,
and the resulting integration PR was **103 files and +14,051 lines**. It is
mergeable. It is not reviewable.

This replaces the earlier stacked-PR design (`maprun-stacked-pr-plan.md`),
which was reviewed against the v0.19.0 implementation and rejected — the
review findings are recorded below in **Why not stacked PRs**.

## Why

v0.19.0 assembles every ticket onto one `integration_branch` and never pushes
it. Three things go wrong at scale:

1. **The review never happens.** Fourteen slices in one diff is a rubber
   stamp, not a review. The per-slice agent panel is real, but the one place
   a human could catch a misread requirement is a PR small enough to read.
2. **Feedback arrives after everything is built.** If slice 3 was wrong, the
   run discovers it when slices 4–14 are already stacked on top of it.
3. **CI runs once, at the end.** Every intermediate state is unverified by
   the project's own pipeline.

## Why not stacked PRs

The obvious fix — one branch per ticket based on its dependency, one PR per
branch — was designed in full and then reviewed against the v0.19.0 code.
It failed the review. The findings, kept here so the decision survives:

- **Merge-strategy coupling.** GitHub's retarget-on-branch-delete keeps child
  diffs coherent only under merge-commit strategy. Squash or rebase merges
  rewrite parent commits on trunk, so every child PR re-shows its parent's
  diff and needs `git rebase --onto` plus a master-driven force-push. The
  lane has no rebase machinery and would have to grow it.
- **Base derivation is stateful.** A child's base branch can be deleted
  mid-run (parent merged into a still-open grandparent). Every `base..HEAD`
  observability and git-state check breaks unless the state records base
  names *and* base SHAs, with a nearest-live-ancestor walk on top of the
  dominator rule.
- **The rework loop was missing.** "Feedback lands early" needs a state and
  a pass step for *changes requested* — who reworks a parent, what happens
  to children built on the old tip. Only the merge case (retargeting) was
  specified.
- **Sibling conflicts move later.** v0.19.0 merges each PASSED ticket into
  the integration branch within one pass, so cross-slice conflicts surface
  early and union-merge rules absorb the expected registry collisions.
  Stacked siblings never meet until a run-end assembly.
- **Diamond dependencies have no sound base.** Two incomparable dependencies
  force either an artificial serializing edge or a slice built without one
  of its declared dependencies present.

The underlying trilemma: of (a) human review gating each slice before
anything builds on it, (b) no serialization behind human review latency, and
(c) no stack bookkeeping — pick two. Stacked PRs pick (a)+(b) and pay (c),
and (c) turned out to be most of a new system. This release picks (b)+(c):
review is per-slice but advisory-after-merge, with the final assembly PR as
the hard human gate. That matches the lane's own risk posture — a slice
reaching PASSED has already survived a grill, a reviewer agent and a
security auditor; slice review catches polish, not redesigns.

## The model

Topology is exactly v0.19.0. One integration branch; ticket branches cut
from it; local `--no-ff` merges back into it (union-merge rules intact);
dispatch gated on dependencies `MERGED`. New, and **opt-in** via a `pr` key
in `plan.json`:

- **Run start** — the master pushes the integration branch to the remote.
- **Per PASSED ticket** — the master pushes the ticket branch and opens a PR
  `ticket → integration_branch` *before* merging. The local merge then lands
  and the integration branch is pushed; GitHub sees the PR's head contained
  in its base and flips the PR to **merged** on its own. The slice diff is
  preserved forever on that closed PR; CI ran against it; review happens
  there, asynchronously, while the run keeps moving.
- **Grill answers and relayed answers** — still committed to the integration
  worktree; the master pushes the integration branch after committing
  (`maprun-pr.sh sync`), so the remote always shows what workers will
  inherit.
- **Run completion** — after `maprun-verify.sh` passes, the master opens the
  final PR `integration_branch → base_branch` whose body links every slice
  PR. Big diff, but every line of it already has a reviewed slice PR; this
  one is the CI + sign-off gate. Merging it stays a human act.

Because only the master ever advances the remote integration branch (humans
never merge slice PRs — they close themselves), every push is a
fast-forward. A rejected push means someone else wrote to the branch, and
the master reports it instead of forcing.

Review feedback on a slice PR becomes a follow-up: a fix ticket appended to
the map, or a normal `/espalier-fix`. Nothing in the run blocks on it.

## What this buys, against the three complaints

1. Reviewable slices — one merged PR per ticket, diff scoped to that ticket.
2. Early feedback — slice PRs exist minutes after the slice passes, while
   later slices are still being built.
3. Per-ticket CI — each slice PR triggers `pull_request` workflows; each
   integration push triggers `push` workflows. Every intermediate state of
   the integration branch is CI-visible.

And it keeps what v0.19.0 already got right: early sibling-conflict
discovery at each local merge, union-merge absorption, grill-answer
inheritance through the integration branch, and a dispatch predicate with no
new states.

## CI trigger scope

A project whose test workflow filters `pull_request: branches: [main, …]`
runs **nothing** on a PR whose base is the integration branch. The failure
is silent — a green slice PR that ran no tests. `maprun-pr.sh setup` scans
`.github/workflows/` for `pull_request` branch filters that do not match the
integration branch and warns, with the one-line fix (add the integration
branch, or a `feat/**` pattern, to the filter). Push-triggered workflows are
unaffected. Field note: the motivating repo hits this precisely — its
`test.yml` is scoped to `dev`/`staging`/`production`; its Cypress workflow
is `on: [push]` and keeps running.

The filter edit itself must exist on `base_branch` before slice PRs open —
a small setup change the human lands once, at plan time.

## The shared-config bug this flushes out

`maprun-integration.sh` applied its push block with plain `git config`,
which writes the **shared** `.git/config` — not the worktree-scoped config
`maprun-dispatch.sh` correctly uses (its own comment names exactly this
mistake). Creating the integration worktree therefore blocked pushes from
the operator's main checkout too. Latent in v0.19.0 (nobody pushed); fatal
in v0.20.0 (the master pushes). Fixed to `--worktree` scope, with a
self-heal that unsets the poisoned shared value, and a migration step for
existing installs.

## Changes by file

| File | Change |
|---|---|
| `hook-templates/maprun-pr.sh` | **new** — `setup` (capability probe, push integration, CI-filter scan), `open <key>` (push ticket branch, create-or-find slice PR, record number/url), `sync` (push integration), `final` (assembly PR). Every subcommand is a silent no-op without a `pr` config; a missing/unauthenticated `gh` exits 5 and never blocks the local merge. |
| `hook-templates/maprun-integration.sh` | `--worktree`-scoped push block (+ `extensions.worktreeConfig`); self-heal of a poisoned shared `remote.origin.pushurl` |
| `hook-templates/maprun.py` | state seeds `pr_number`/`pr_url`; new `set-pr <key> <n> <url>` subcommand; `status` prints `PR#` |
| `templates/skills/espalier-maprun.md` | plan step asks the PR opt-in (naming the rail change); pass step 4 becomes open → merge → sync when enabled; step 6 opens the final PR; safety rails rewritten |
| `scripts/bootstrap-espalier.sh` | ships `maprun-pr.sh` in the write-if-absent engine loop |
| `scripts/migrate-v0.19.0-to-v0.20.0.sh` | **new** — adds `maprun-pr.sh`, refreshes the lane skill (backup-on-diff), patches the stock config lines in an existing `maprun-integration.sh`, unsets a poisoned shared pushurl and re-blocks existing `_integration` worktrees worktree-scoped |
| `scripts/test-bootstrap.sh` | Test 27: engine file shipped; shared-config hygiene regression; stub-`gh` + bare-remote e2e (open records PR, merge closes it, sync pushes, final assembles); disabled-path no-op; migration trio |
| `eval/maprun/fixtures/run-07-pr-flow.md` | new fixture: open-before-merge ordering, a failed `open` that must warn-and-continue, stop-after-one-pass |
| `skills/espalier-migrate/SKILL.md` | v0.19.0→v0.20.0 hop |
| `CHANGELOG.md`, `README.md` | v0.20.0 entry |

## Execution modes

Orthogonal to the PR flow, the lane gains a second way to execute tickets,
chosen at plan time (`worker_mode`):

- **Headless** (`session` / `staged`, as in v0.19) — detached workers that
  outlive the master, observed on the `watch` dashboard; the master never
  runs a pipeline itself. For big maps, parallelism, unattended runs.
- **Inline** (`inline`, new) — dispatch prepares the worktree (branch off the
  integration branch, push block, dependencies) and spawns nothing; the
  master runs the ticket's pipeline in-session, spawning the stage agents
  directly, one ticket at a time. Questions go straight to the human instead
  of parking; state is marked directly instead of via sentinels. No headless
  CLI dependency — the one mode a Copilot-only install can run. Crash
  recovery reuses the existing machinery: a dead session leaves `DISPATCHED`
  with no live pid, and the next session's reap retries from
  `pipeline-state.md`.

The "master never runs a pipeline" doctrine is scoped to the headless modes;
inline inverts it deliberately, and the SKILL keeps the guardrails that still
apply (ticket worktree only, stages 1–6 only, one ticket at a time, fresh
session every 1–2 tickets for context hygiene).

## Safety rails, restated

With `pr` enabled, the master pushes `espalier/*` ticket branches and the
integration branch, and opens PRs — that is a deliberate, plan-time human
opt-in, asked explicitly during the plan step. Workers still cannot push
(git-config block, worktree-scoped). Merging the final assembly PR into
`base_branch` remains a human act. Without a `pr` config the lane behaves
exactly as v0.19.0 — nothing reaches the remote.

## Open items

- **Waiting on checks.** The master merges a slice locally without waiting
  for the slice PR's CI to finish; the verdict lands on the closed PR and on
  the integration branch's own push-triggered runs. A `pr.wait_checks`
  option (hold the merge until `gh pr checks` is green) is deliberately
  deferred until the field shows the advisory signal is not enough.
- **Forge portability.** `gh` is GitHub-specific. `maprun-pr.sh` isolates
  every forge call so a GitLab/Gitea variant can replace one file, in the
  same spirit as the `claude`/`codex` worker-platform split.
- **Stacked PRs remain a possible v0.2x** if the field demands hard
  per-slice gating before trunk entry — the rejected design plus its review
  findings above are the starting point.
