# eval/security — Known Issues

Status 2026-08-25 (v0.23.0 fix round): the deferred v0.22 recalibration is
DONE — judge validated at **24/24 = 1.00 agreement** against the hand-scored
set (`judge-validation/`, threshold ≥ 0.75), shadow-03 is re-keyed and
green, and the full 20-fixture suite runs at catch-rate 1.00. The one FP
observed in a full run (shadow-02) does not reproduce and is recorded as
judge variance below. History kept as the diagnostic record.

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
