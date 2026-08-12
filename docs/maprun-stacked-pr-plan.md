# v0.20.0 stacked-PR draft — superseded

This draft proposed replacing the run lane's integration branch with a stack
of dependency-based branches, one PR per ticket. It was reviewed against the
v0.19.0 implementation and **rejected**; v0.20.0 ships slice PRs on the
integration branch instead.

The shipped design — and the full record of why stacking lost (merge-strategy
coupling, stateful base derivation, the missing rework loop, later
sibling-conflict discovery, unsound diamond-dependency bases) — lives in
[`maprun-pr-lane-plan.md`](./maprun-pr-lane-plan.md), under **Why not stacked
PRs**. If the field ever demands hard per-slice gating before trunk entry,
that section is the starting point for reviving the stack.
