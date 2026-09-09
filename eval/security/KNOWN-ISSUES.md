# eval/security — Known Issues

Status 2026-09-09 (v0.25.0): the FP gate was red AT BASELINE under the
2026-09 default model (v0.24.0 templates + fixtures, opus pinned: catch 1.00,
8 false positives across 7 fixtures) and the v0.25.0 candidate showed 2. Read
side by side, the extras were one class: **speculative or out-of-class P0/P1s**
— "no auth middleware asserts `req.session.userId`" (five fixtures: a control
that lives outside the single-handler fixture body), "the record might carry a
balance field", a whole-record response, audit-log ordering, an inventory
oracle, a missing transaction / idempotency (production seeds), an unvalidated
`toUserId` (a destination label), an unproven signup `email` at P1. Fixed at
the source, three ways: (1) `harness-security.md` Priority Rubric gains
**Shown, not assumed** — a P0/P1 names the client value and the sink in the
audited code with the tamper stated; a control outside the audited files is
`unverified: … — not in the audited files` under Controls confirmed, never a
finding for being absent; production seeds are the reviewer's; a lookup /
destination key that authorizes nothing is not a P0; one root defect is filed
once (no cap on findings — the bar each one clears); (2) `rubric.md` codifies
the same class as spurious at P0/P1 and never-FP at P2/P3; (3) `vuln-06`'s
body validates `amountCents` (a genuine extra hole a stronger model found —
the shadow-03 precedent) and `shadow-01` / `vuln-06` watch lines name the
email / destination / atomicity extras, `vuln-05`'s the server-set
`status` / replay extra. Re-validated: **RESULT PASS 20/20, catch 1.00,
0 false positives** (rows under FIXED below). History kept as the
diagnostic record.

Status 2026-08-25 (v0.23.0 fix round): the deferred v0.22 recalibration is
DONE — judge validated at **24/24 = 1.00 agreement** against the hand-scored
set (`judge-validation/`, threshold ≥ 0.75), shadow-03 is re-keyed and
green, and the full 20-fixture suite runs at catch-rate 1.00. The one FP
observed in a full run (shadow-02) does not reproduce and is recorded as
judge variance below. History kept as the diagnostic record.

## FIXED (2026-09-09): speculative / out-of-class P0/P1 — the shown-not-assumed bar

Same 20 fixtures, same pinned model (`ANTHROPIC_MODEL=opus`), the
recalibrated `rubric.md`; the judge-validation replay agrees with
`handscore.tsv` 24/24 under it.

| Auditor | Records | Catch | FP |
|---|---|---|---|
| v0.24.0 template | baseline run, re-judged | 1.00 | 16 (10 fixtures) |
| v0.25.0 before the bar | first candidate run, re-judged | 1.00 | 17 (8 fixtures) |
| v0.25.0 bar, first wording | live run | 1.00 | 3 (repo-03, vuln-05, vuln-06) |
| v0.25.0 bar, shipped wording | live run | 1.00 | **0 — RESULT PASS 20/20** |

The three that survived the first wording shared one shape: a P0/P1 whose
own text carried the premise it needed — repo-03 filed the queue
consumer's `event.userId` at P1 while writing "no publisher/queue ACL is
present in the audited files … hence P1, not P0"; vuln-06 filed the
check-then-debit race at P1 with `unverified: db.accounts.debit / credit
atomicity` under Controls confirmed; vuln-05 filed the hard-coded `status`
plus "no idempotency key" at P1 as a third finding beside the planted
missing recompute. A wording gap, not judge variance (the judge scored
each as the hand score would). The bar now says "client-supplied" and
"reachable" are shown the same way (an unseen queue / job producer is
P2/P3 plus an `unverified:` line), replay and a second effect of a filed
root defect are the reviewer's / a sibling read, and a finding that states
its own unverified premise is not a P0/P1 — an unverified premise is not a
P1 "mitigating factor". A 4-fixture probe (repo-03, vuln-03, vuln-05,
vuln-06) then the full suite: 0 false positives, and the kept records carry
the same observations at P2/P3 with their `unverified:` lines — precision,
not suppression. The judge-variance discipline below still applies to any
future red gate.

## FIXED: judge-collapse counting artifact

The rubric now codifies the collapse rule the hand scores always assumed:
findings are grouped by ROOT DEFECT before counting — each planted vuln is
ONE catch however many findings slice it, extra slices are never FPs — and
collapse NEVER merges distinct `planted_vulns` entries (`planted` is the
literal list length). Re-validated after the change: 24/24 agreement
(first pass 22/24; the two misses were shadow-01's answer key packing two
fields into one entry — split into two entries, see below).

## FIXED: shadow-03 answer key

Root-caused: the auditor's recurring "false positive" was a REAL hole in
the fixture's own "clean" code — `PLANS[req.body.planId]` resolves
prototype-chain keys (`"constructor"`, `"__proto__"`, …), the `== null`
allow-list check passes, and a Function is persisted as `priceCents`.
2026-08 models legitimately catch it. The fixture now guards with
`Object.hasOwn` (keeping its moved-owner-check FP-trap purpose) and the
watch line covers the hardened lookup. Verified PASS solo and in the full
suite.

## FIXED: shadow-01 answer key granularity

`planted_vulns` packed two sensitive fields (`verified`, `plan`) into one
list entry; under the literal-length rule the judge counted 1 where the
hand score said 2. Split into two entries (same root pick() bug, two
fields, two contract entries). Judge and hand scores now agree 4/4 on it.

## FIXED: judge output-parse strictness

All seven eval runners now take the LAST `{…}` line of the judge reply
before parsing, so a prose preamble cannot fail a fixture.

## Judge variance (open, bounded — the attribution discipline)

One full run showed a single FP on shadow-02-header-role; a KEEP_WORK
rerun PASSed cleanly (auditor filed exactly the planted P0, judge 0 FP),
and earlier full runs had shadow-02 green. Same class as
`eval/review/KNOWN-ISSUES.md`'s history: fixture-random, non-reproducing
judge/auditor variance under 2026-08 models. Discipline: an FP-gate
failure is attributed to a template change ONLY after (a) a baseline A/B
under the same model and (b) a KEEP_WORK rerun of the failing fixture —
a non-reproducing FP is variance; a reproducing one gets its record read
(shadow-03 shows it can be the fixture, not the auditor). Re-validate
`judge-validation/` whenever `rubric.md` changes.
