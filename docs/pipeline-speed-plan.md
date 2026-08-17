# Pipeline Speed Plan (v0.21.0)

**Constraint (from the field request that motivated this):** reduce the
wall-clock and token cost of an `/espalier` feature run and an
`/espalier-fix` run **without impacting the quality of the code**. Every
change below is a read-scope, dispatch, or wait-scheduling optimization; the
quality machinery — separate coder/reviewer/security agents, fresh panel
round after every fix, per-round `VERDICT:` sentinels, programmatic gates,
round caps, the `Reviewed-Diff` certificate — is byte-for-byte contract-equal
to v0.20.

## Where the time went (measured against the v0.20 templates)

A happy-path feature run costs **5 sub-agent cold starts** (coder, 2-agent
panel, test-coder, test-reviewer); each spawn began by re-reading the same
skill/spec/rules/reference set from scratch. One failed review round added 3
more cold starts, and the panel re-reviewed the **whole diff** each round.
On wall-clock, human latency usually dominated: sequential grill questions
(one round-trip each), the approval gate, the Stage 7 push confirm, and the
Stage 10 acceptance.

## Shipped changes

| Change | Cost removed | Why quality is unaffected |
|---|---|---|
| Context pack (both lanes) | Repeated layers/specs/rules/reference discovery per spawn (5-11× per change) | Pack carries paths + facts, never conclusions; agents still read the named files; current code outranks the pack; no pack → old behavior |
| Delta-scoped re-review rounds | Whole-diff re-read on every round n≥2 | Every line of the final diff was reviewed fresh in the round it last changed; scope is a floor (suspicion → expand); build/lint re-runs whole-tree per round; fingerprint blocks unreviewed edits at push |
| Security delta mode | Full re-audit when the round exists because the *correctness* reviewer failed | Security still sees the current code and issues a fresh per-round sentinel; any new trust-boundary read or contract change → full re-audit; prior findings → full re-audit |
| Parallel disjoint sub-tasks (full lane) | Serial dispatch of independent sub-tasks | Disjoint file sets verified before dispatch (shared modules = overlap → serial); exit gate + panel run on the combined diff |
| Push-target pre-authorization (both lanes) | Mid-run stall at Stage 7 waiting for a human | Collected at the approval gate the human is already attending; all programmatic push gates unchanged; never extends to Stage 10 |
| Grill light-tier batching | One human round-trip per independent question | Only pairwise-independent `light`-tier questions batch; `full` tier + decision mode stay sequential (the eval rubric's Progression dimension scores full-tier chaining, and at that ambiguity level chaining IS the quality) |

## Considered and rejected

- **Skip the security agent on rounds whose fix diff doesn't intersect its
  audited surface.** Rejected: a fix can introduce a NEW client-data read
  into a previously non-sensitive file — file-level intersection cannot see
  that, and the Stage 4 exit gate's core invariant is "the MOST RECENT run of
  BOTH panel agents saw the CURRENT code". Delta mode keeps that invariant
  (fresh sentinel every round) at nearly the same saving.
- **Batching grill questions generally.** Rejected for `full` tier: the
  divergent-interpretations technique depends on the last answer; the grill
  eval rubric scores that progression directly.

## Deferred

- **Fold interface-test writing into Stage 3 + merge Stage 5/6 into the
  panel.** Largest remaining spawn saving (~2 spawns + one loop per run),
  but it restructures the stage contract (the abuse-test contract is only
  emitted by Stage 4's security pass, so tests would split into
  interface-tests-with-code and contract-tests-after-panel). Punt until
  `bash espalier/hooks/espalier-stats.sh` field data shows the remaining
  cost concentrates there. Recorded in `docs/deferred-items.md`.

## Measure before tuning further

`espalier-stats.sh` reports review-round distributions. If real runs mostly
pass in 1 round, further work should target spawn count and human latency
(the deferred stage-fold); if runs average 2+ rounds, the delta-scope savings
dominate and the round-cost work is done.
