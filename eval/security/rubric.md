# Security Eval Rubric

How a `harness-security` audit run is scored. The judge reads the fixture (whose
frontmatter is the answer key) and the `security-record.md` the auditor produced,
and emits ONE compact JSON line. Score objectively; reward finding the planted
vulnerabilities and punish both misses AND false alarms.

## What the judge outputs

```json
{"planted":N,"caught":N,"false_positives":N,"verdict_match":0|1,"verdict":"PASS|FAIL"}
```

## Field definitions

- **planted** — the number of entries in the fixture's `planted_vulns` (0 for a
  `clean` fixture).

- **caught** — how many of the planted vulns the auditor actually flagged as a
  **P0 or P1** finding. Match by MEANING, not string: a planted
  `{field: orderId, axis: owner}` is caught if the record has a P0/P1 finding about
  that field/endpoint describing the missing ownership check (IDOR/BOLA) — regardless
  of wording. A planted vuln mentioned only in passing, or rated P2/P3, is NOT caught.
  A fixture with `planted: 0` scores `caught: 0`.

- **false_positives** — findings that should not be there:
  - On a **clean** fixture (`kind: clean`): ANY P0 or P1 finding is a false positive.
    Count each. A correct clean run has a PASS verdict and, for a no-surface change,
    a `NO SENSITIVE SURFACE` note — that is NOT a false positive.
  - On a **vuln** fixture: count P0/P1 findings that are NOT one of the planted vulns
    AND are not a genuine additional flaw. Do not penalize the auditor for finding a
    real extra issue you can confirm in the code; DO count invented/spurious ones.
  - Anything the fixture lists under `false_positive_watch` that the auditor flagged
    counts as a false positive.

- **verdict_match** — `1` if the auditor's `**Verdict:**` line matches the fixture's
  `expected_verdict` (FAIL for `vuln`; PASS or PASS_WITH_FIXES for `clean`), else `0`.
  A clean fixture with `expected_surface: none` also requires the auditor to have
  self-nooped (emitted the `NO SENSITIVE SURFACE` block) — if it audited and passed
  anyway that still counts as verdict_match 1, but note it.

- **verdict** — your holistic PASS/FAIL for this single fixture. PASS only if
  `caught == planted` AND `false_positives == 0` AND `verdict_match == 1`. (The runner
  recomputes the gate from the numbers; this field is a cross-check.)

## Also check (fold into false_positives / notes, do not add fields)

- **Axis correctness.** If the auditor caught the vuln but classified it on the wrong
  risk axis (e.g. called a `price` money-defect an "owner" issue), it is still
  *caught* but flag it — persistent axis confusion is a real defect. Only downgrade to
  not-caught if the mislabeling changes the prescribed control to a wrong one.
- **Contract validity (vuln fixtures).** The record should carry a well-formed
  `## Security-Sensitive Fields` block with one entry per caught sensitive field
  (sub-fields: field / endpoint / axis / required_control / abuse_test). A caught
  vuln with no contract entry is still caught, but a missing/garbled contract is a
  quality defect — treat a completely absent contract on a vuln fixture as one
  false_positive-equivalent penalty (it breaks the Stage 5/6 handoff).

## Repo-audit fixtures (`mode: repo-audit`)

These score the `/espalier-audit` repo-audit mode: the fixture body is a set of
`=== FILE: <path> ===` blocks (a whole small repo, not one change), and the
record under judgment is the auditor's returned findings document (there is no
security-record.md in this mode). All field definitions above apply, with:

- **verdict_match** — compare the `**Batch verdict:**` line instead of
  `**Verdict:**`: `FINDINGS` matches a `vuln` fixture, `CLEAN` matches a `clean`
  fixture. Missing/garbled batch-verdict line → `verdict_match: 0`.
- **false_positives** — additionally: a well-controlled endpoint belongs under
  `### Controls Confirmed` (NOT a false positive); a listed file with no
  sensitive client input belongs under `### No Sensitive Fields` — a P0/P1
  finding manufactured on such a file IS a false positive. Server-side batch
  jobs with no client input are not client-tamperable state transitions.
- **Contract validity** — repo-audit emits a `### Security-Sensitive Fields`
  entry **per finding only** (not per in-scope field). A caught finding with no
  contract entry: still caught, but a completely absent contract section on a
  fixture with planted vulns is one false_positive-equivalent penalty (it
  breaks the /espalier-fix handoff). Do NOT penalize the absence of contract
  entries for confirmed-controlled fields — that is the mode's specified
  behavior.

## Judge discipline

- Do not reward verbosity. Four crisp correct P0s beat ten vague findings.
- Do not invent planted vulns the fixture did not list.
- If the security-record is empty, malformed, or missing, score
  `caught:0, false_positives:0, verdict_match:0` and `verdict:"FAIL"`.
- Output ONLY the JSON line. No prose, no code fence.
