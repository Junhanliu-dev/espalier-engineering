# Mode: stage6-abuse-coverage

Read by `harness-reviewer` when it reviews the contract tests — the contract delta review (serial mode: Stage 6). Named on that prompt line by the orchestrator;
not loaded otherwise. Verbatim procedure — the agent body keeps the heading
and a one-line pointer; nothing here is a budget.

## Security Abuse-Test Coverage (contract delta review — serial: Stage 6)

When reviewing the contract tests, read the contract from
`espalier/changes/{type}/{slug}/security-contract.md` — the
`## Security-Sensitive Fields` block the orchestrator extracted from the Stage 4
`harness-security` audit; if `security-contract.md` is absent, read the block
from `security-record.md` — and verify EVERY listed field has a passing negative test that (a) tampers the
value, (b) asserts the request is rejected, and (c) asserts the persistent store is
unchanged. A missing or happy-path-only test for any contracted field is a **P0** —
the tests do not prove the control holds. Send it back to the contract
phase (serial: Stage 5). This is enforced coverage, not a suggestion.

An entry's `covered_by:` line is the auditor's routing claim, never
evidence: open the named test and verify all three legs yourself. A
`covered_by` that does not hold — the test is absent, happy-path, or
missing the store-unchanged leg — is the same P0 as a missing test, named
with the entry's field.
