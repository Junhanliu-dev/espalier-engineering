# v0.25.0 benchmark — eval A/B (2026-09-09)

Same-day A/B on one pinned model (`ANTHROPIC_MODEL=opus`, the latest Opus
alias, Claude Code 2.1.265, headless `claude -p`, `ESPALIER_UNATTENDED=1`).
Baseline = the v0.24.0 templates AND fixtures (`git archive v0.24.0 -- eval
skills/espalier-init/templates`); candidate = the v0.25.0 working tree. The
discipline is `docs/deferred-items.md` / `eval/security/KNOWN-ISSUES.md`'s:
a gate failure is attributed to a template change only after the baseline
A/B under the same model and a `KEEP_WORK=1` rerun of the failing fixture.

## Results

| Suite | Baseline (v0.24.0) | Candidate (v0.25.0) | Read |
|---|---|---|---|
| coder — seed fixtures 01–05 | 5/5 PASS, over-scope 0, over-build 0 | 5/5 PASS, over-scope 0, over-build 0 | unchanged |
| coder — new 06 scoped-doc trap, 07 two-seam | — (fixtures did not exist) | 2/2 PASS (violations 0, task done, scope ok, build ok, `spec-line=ok`); 07 landed as two seam commits | new coverage; Commit Discipline observed |
| review — seed fixtures (10) | catch 1.00, FP 0, verdict match 10/10 | catch 1.00, FP 0, verdict match 10/10 | unchanged |
| review — new spec-unread-09 | — | catch 1/1 (`[spec-unread]` P2 filed naming the missing section), FP 0, `PASS_WITH_FIXES` | the D.5 check works |
| security (20) | catch 1.00, FP 8 (7 fixtures), RESULT FAIL | catch 1.00, FP 0, RESULT PASS 20/20 | catch equal; the FP gate is green for the first time under a 2026-09 model — the precision bar, see below |

Coder 06/07 on the first candidate pass: judge PASS on both (violations 0,
task done, scope ok, build ok) and the coder committed its units — one
commit for 06, two seam commits for 07 (`feat(services): …` then
`feat(controllers): …`) — but the script-side `- Spec applied:` check
reported `bad-section` because it read a multi-section citation
(`§ Function shape / Status values / Results`) as one section name. Checker
fixed (every cited section on the line must be a spec heading; `none — no
spec for {layer}` lines accepted; one entry per layer); re-run: 2/2 PASS with
`spec-line=ok` — the coder cited `§ Function shape / Status values /
Results` for services and `none — no spec for controllers` for the second
seam.

## What the A/B changed on the way

- **The v0.25 coder commits its own work** (Commit Discipline), so
  `eval/coder/run.sh`'s index diff read a committed change as "no code" —
  7/7 NO-CODE on the first candidate pass. The runner now diffs from its
  baseline root commit; the baseline numbers are unaffected (an uncommitted
  tree diffs the same either way).
- **`spec-unread-09` had a real P1 in its "clean" code**: `cancelOrder`
  read the order, decided on `status`, and wrote the whole snapshot back —
  the read-modify-write the eval's own `production-standards.md` tiers as
  P1. The reviewer was right; the fixture now applies the transition as an
  atomic conditional repository update and its `false_positive_watch`
  says so. Same class as the 2026-07 / 2026-08 fixture-authoring gaps.
- **Security FPs reproduced at baseline, then were fixed at the source.**
  The first candidate pass scored 2 (shadow-01 an `email` P1 the key
  declares client-set; vuln-06 a negative-`amountCents` P0 and an
  unvalidated `toUserId` beyond the planted `fromUserId` spoof) against the
  baseline's 8 — every extra one class: a P0/P1 resting on what the auditor
  could not see. The fix is the auditor's **Shown, not assumed** bar plus a
  rubric that codifies the class (`eval/security/KNOWN-ISSUES.md`). Under
  that rubric the stored records re-score as follows (same 20 fixtures,
  same pinned model; the judge replay agrees with the hand scores 24/24):

  | Auditor | Records | Catch | FP |
  |---|---|---|---|
  | v0.24.0 template | baseline run, re-judged | 1.00 | 16 (10 fixtures) |
  | v0.25.0 before the bar | first candidate run, re-judged | 1.00 | 17 (8 fixtures) |
  | v0.25.0 bar, first wording | live run | 1.00 | 3 (repo-03, vuln-05, vuln-06) |
  | v0.25.0 bar, shipped wording | live run | 1.00 | **0 — RESULT PASS 20/20** |

  The three that survived the first wording shared one shape — a P0/P1
  whose own text carried the premise it needed (an unseen queue producer,
  "hence P1, not P0"; `unverified: db.accounts.debit atomicity`; a
  hard-coded `status` plus "no idempotency key") — so the bar now says
  "client-supplied" and "reachable" are shown the same way, replay and a
  second effect of a filed root defect are the reviewer's / a sibling read,
  and a finding that states its own unverified premise is not a P0/P1. The
  kept records show those observations filed at P2/P3 with their
  `unverified:` lines, not dropped.
- Runners keep the headless agent's stdout/stderr per fixture
  (`$WORK/<fixture>.agent.log`) and honour `KEEP_WORK=1` in all three suites
  (the coder and review runners used to delete their work unconditionally).

## Field numbers

The context effect on the portal is measured after the migration and the
field smoke (`scripts/context-report.py` on the weeks before and after;
§0 of `docs/quality-first-context-plan.md` is the "before"). Not yet run.
