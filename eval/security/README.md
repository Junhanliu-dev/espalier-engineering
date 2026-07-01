# Security Eval Harness

Dev/QA infrastructure for the `harness-security` auditor (and the
`espalier-security` skill + `security-standards` rule it reads). NOT shipped to
target projects — it lives in the espalier-engineering repo and validates the
security audit before release.

It answers the "is it phantom?" question: does the auditor **actually catch**
planted vulnerabilities on real code, classify them on the right axis, emit a
usable abuse-test contract, and — just as important — **not cry wolf** on clean
changes or wrongly wave through a sensitive one.

## Layout

```
eval/security/
├── README.md      this file
├── rubric.md      how a security audit is scored
├── run.sh         the runner
└── fixtures/      golden code changes with planted vulnerabilities (+ clean ones)
```

## Run

```bash
bash eval/security/run.sh
```

Per fixture the runner: (1) builds a throwaway project containing the fixture's
code change + a generated security install; (2) runs `harness-security` against it
via `claude` headless, following the real Stage-4 prompt; (3) scores the produced
`security-record.md` with an LLM judge against `rubric.md`; (4) aggregates. Exits
non-zero unless catch-rate ≥ 0.90 **and** zero false positives **and** every
fixture's verdict matches.

## Fixture format

One `.md` file per fixture. Frontmatter is the answer key; the body is the code
change under audit.

```yaml
---
fixture_id: vuln-01-idor-order
kind: vuln | clean
file: src/order.controller.js     # where the runner writes the body
expected_verdict: FAIL | PASS
expected_surface: sensitive | none
planted_vulns:                     # what the auditor SHOULD catch (empty for clean)
  - field: orderId
    axis: owner | identity | permission | money | state
    hint: <one-line description of the defect>
false_positive_watch:              # things it must NOT flag
  - ...
shadow: false
---
<the code file being reviewed>
```

## Why both `vuln` and `clean` fixtures

- **`vuln`** — measures the catch-rate. A miss here is a shipped vulnerability.
- **`clean`** — the other half, and the one people forget. A blocking gate that
  false-positives on a CSS tweak (or a correctly-controlled endpoint) is unusable
  and gets disabled. `clean` fixtures also exercise the **self-noop scope gate** and
  the **queue-consumer** edge the pre-release audit flagged.

## Discipline (same as eval/grill)

- **Reach 20–30 fixtures.** This seed set has 7 (5 vuln across the five axes +
  mass-assignment + queue-consumer; 2 clean). The gate is provisional until full.
- **Shadow subset.** Roughly one third should be `shadow: true` — authored from real
  CVEs / real PRs or by someone other than the security-skill author, so the auditor
  cannot be tuned to pass known fixtures. This seed is all `shadow: false`.
- **Validate the judge** before trusting it — hand-score a handful and confirm the
  judge agrees (≥ 75%), especially on the axis-correctness and false-positive calls.
- **Regression gate.** Run `run.sh` on every edit to `harness-security.md`,
  `espalier-security.md`, or `security-standards.md` — prompt edits cause silent
  regressions in exactly this kind of judgment behavior.
