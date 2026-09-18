# Known issues — prstack eval

## 1. Fixture 01 was ambiguous on first run (fixed 2026-09-18)

The first full run scored 3/4. `01-new-external-service` expected `NO-IMPACT`
for `wiki/critical-paths.md`; the sweep returned `PATCH`, reasoning that
settlement now charges the customer through Stripe.

**The sweep was defensible and the fixture was wrong.** That fixture's
`critical-paths.md` documented the settlement path, and the diff inserts a
synchronous external call into the middle of it. Whether that makes the
documented chain *false* or merely *incomplete* is a real question, and a
fixture that turns on it is testing the fixture author's opinion rather than
the sweep's calibration.

Fixed by removing the ambiguity, not by relabelling the answer: that fixture's
`critical-paths.md` now documents the registration path, which the diff does
not touch, so `external-services.md` is the single correct PATCH. Re-running
gave 4/4.

Recorded because the alternative — editing the expectation to match the output
— is how an eval quietly stops measuring anything.

## 2. `claude -p` variance

Verdict lines are free text after the file name, so the parser matches on the
`NO-IMPACT` / `PATCH` token rather than on an exact shape. A run that emits the
block in a different order, or wraps it in a fence, still parses. A run that
omits a file's line entirely is scored `MISS` and fails the fixture — that is
correct, the mode requires one line per file.

Infra failures (non-zero exit, empty output) retry `CLAUDE_RETRIES` times and
are reported separately from scores, never folded into the gate.

## 3. The harness does not exercise the real Stage 7 wiring

It runs the mode text against fixture inputs. It does not run
`espalier-pr.sh`, does not build a projection, and does not open PRs — those
are covered by the migration chain e2e and by the live forge probe recorded in
`docs/pr-split-plan.md`. A green run here means the sweep is calibrated, not
that Stage 7 is wired.
