# Development Process

## Branch Strategy
{detected from git or CI config}

## Commit Conventions
{detected from git log}

## CI Checks
{existing checks + what they verify}

## Deploy & Verification
{from DISCOVERY.deploy — mechanism, exact command (or "automatic on merge"),
health check, and which environment a merged change reaches. This is what
pipeline Stage 9 runs/verifies. If DISCOVERY.deploy was null, write exactly:
"No deploy configuration discovered — Stage 9 records SKIPPED: no-deploy-config."}

## Quality Bar
{what must pass before merge — derived from CI + project conventions}

## Maintenance Commits
<!-- ESPALIER MAINTENANCE COMMITS v2 — managed anchor; fixed policy text (not scout-discovered), keep this comment -->

- Every change ships as TWO pull requests: the code PR (every path outside
  `espalier/`) and its espalier PR (all of `espalier/**` — records, convention
  index, and any doc the Stage 7 sweep refreshed). They are siblings on the
  canonical branch, not a stack; the espalier PR's body says which to merge
  first. Nothing enforces the order.
- Drift YOUR change caused rides YOUR espalier PR, as its own isolated
  `docs(espalier):` commit — the Stage 7 sweep writes it, scoped to what this
  change's diff falsified. Drift you did NOT cause stays on the weekly
  gardener lane: doctor scans and routine prune refreshes ride ONE weekly
  maintenance PR on the canonical branch (`canonical-branch` in
  `espalier/.espalier-config`). A prune for your OWN critical/expired flag may
  ride your espalier PR as its own isolated `docs:` commit; convention
  promotions ride the deciding change's espalier PR. Maintenance commits are
  never folded into feature commits — the espalier PR is a separate PR, so
  that invariant is now structural rather than a matter of discipline.
- The weekly gardener rota: one rotating dev per cadence interval runs the
  maintenance loop (worktree of the canonical branch → `/espalier-doctor` →
  `/espalier-prune` over flagged files → re-run the doctor if the prune
  cleared everything, so the shared `espalier/.doctor-stamp` says `clean` →
  one `docs: weekly espalier maintenance` PR). The rota names who — that is
  what kills "someone else surely ran it". A skipped week self-corrects: the
  stamp ages out and `doctor_due()` nags everyone again.
- Rule-canon gate: every PR touching `espalier/rules/` gets the rule owner's
  review. CODEOWNERS routes it automatically ONLY when "Require review from
  Code Owners" branch protection is on — without protection the file is
  advisory; turn protection on. Rule owners: before approving a rules PR,
  fetch canonical state and check for concurrent open rule PRs — no automated
  detector can see two PRs that are both still open.
- Union-merge caveat: GitHub's web conflict editor ignores custom merge
  drivers (including `merge=union` on `espalier/.ask-gaps.tsv`) — resolve
  union-file conflicts locally, never in the web UI.
- Pipeline commits are atomic: the coder commits one bounded unit per
  commit at a clean point, staged by path, message per the Commit
  Conventions above (`harness-coder.md` → Commit Discipline); the
  pipeline pushes them as made and never squashes — squash-merge is the
  pull request's policy.
