# Mode: re-review

Read by `harness-reviewer` and `harness-security` when the prompt carries `CHANGED SINCE LAST REVIEW:` — a panel round ≥ 2 after a coder fix. Two sections: the reviewer's, then the security agent's — read yours. Named on that prompt line by the orchestrator;
not loaded otherwise. Verbatim procedure — the agent body keeps the heading
and a one-line pointer; nothing here is a budget.

## Re-review Rounds (you may be re-spawned on a fix)

You are stateless and will be spawned again after the coder fixes your findings.
A fix is the single most likely place for a NEW bug to enter, so a re-review is a
real review, not a rubber stamp:

1. You will be handed the "changed since last review" set — the files/hunks the
   coder just touched. Scrutinize those hardest.
2. Confirm the fix did not regress code that previously passed — check callers and
   any surface the changed code feeds (run the Runtime-Surface Review on the delta).
3. Your verdict still covers the WHOLE diff, not only the delta. Return PASS only
   when the code AS IT STANDS NOW is clean. If the fix introduced a new P0, report
   it — you will be re-spawned again after the next fix.
4. **Class-sweep verification.** For every P0/P1 the prior round raised (yours
   AND the security agent's), coding-report.md must carry a `### Class Sweep`
   block (harness-coder.md → Fix Rounds). State the class in YOUR OWN words
   first, then search for it your own way — only then re-run the coder's
   `Search:` and compare; a coder's blind spot that wrote the bug can also
   narrow the search. Open each "not affected" entry and confirm the reason
   holds; open each FIXED sibling as new code — same class does not mean
   the same fix was right there. `Out-of-scope siblings:` are not findings
   (the orchestrator files the follow-up) — but a sibling listed there that
   sits in a touched layer is a P1. A missing block, an occurrence the sweep did not list, or a
   "not affected" sibling that IS an instance of the class → P1
   `[class-sweep]` naming the exact sibling file:line. Fixing one instance
   of a class the panel already named is not a fix — it is the next round's
   finding, filed early.

**Delta read scope (a floor, not a ceiling).** On a re-review round your
REQUIRED reads are: (a) every file the fix changed, (b) every file named in
the prior round's findings — verify each is actually resolved, not just
claimed — and (c) the direct callers/dependents of anything the fix changed
(a fix that alters a helper's contract breaks callers it never touched).
On a CONTRACT DELTA REVIEW, the delta is the contract test files +
security-record.md — your job there is the abuse-coverage check.
Do NOT re-read the entire diff by default — the unchanged remainder was
reviewed fresh in the round it last changed, the orchestrator re-runs
build/lint on the whole tree before every round, and the Reviewed-Diff
fingerprint blocks any unreviewed edit at push. EXPAND beyond the required
scope the moment anything you read makes you suspect wider impact — suspicion
always outranks the scope. The whole-diff verdict rule above is unchanged.

Never assume the fix is correct because it addresses your previous finding. Review
the new code as fresh code.

## Re-review Rounds (you may be re-spawned on a fix)

You are stateless and will be spawned again after the coder fixes a P0. A fix is a
prime place for a new hole to open. On a re-audit:

1. You will get the "changed since last review" set — scrutinize it hardest.
2. Confirm the fix did not shift the trust boundary elsewhere (e.g. moved the
   client value into a different unchecked call).
3. Your verdict covers the WHOLE change, not just the delta. PASS only when the
   code AS IT STANDS NOW trusts no sensitive client value.
4. **Class-sweep verification (your own findings).** For every P0/P1 YOU raised
   last round, coding-report.md must carry a `### Class Sweep` block
   (harness-coder.md → Fix Rounds). Re-run its `Search:`; a bypass of the
   fix, an unlisted sibling surface (another handler / route / resolver
   reading the same client value), or a wrong "not affected" claim → P1
   `[class-sweep]` naming the sibling. A trust-boundary hole fixed at one
   door with its sibling doors open is still open.

**Delta mode (when YOUR prior round was clean).** If your last sentinel on
this change was PASS/PASS_WITH_FIXES with p0=0 p1=0 — the round exists
because the CORRECTNESS reviewer failed, not you — audit the delta instead of
re-auditing everything: read the fix's changed files and answer two
questions. (1) Does the fix introduce any NEW client-supplied value,
endpoint, consumer, or trust-boundary read your prior audit did not cover?
(2) Does it alter the handling of any field already in your
`## Security-Sensitive Fields` contract? Both no → write this round's record
citing the prior audit's scope, carry the contract forward unchanged, and
end with a fresh `VERDICT:` sentinel for THIS round — you saw the current
code and this round's verdict is yours. Either yes — or your prior round had
findings — → full re-audit exactly as on round 1. Delta mode narrows what
you must read, never what you may read, and never your responsibility.

Never assume the fix is correct because it addresses your prior finding. Audit the
new code as fresh code.
