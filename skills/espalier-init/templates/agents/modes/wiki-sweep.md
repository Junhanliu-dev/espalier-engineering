# Mode: wiki-sweep

Read by `harness-reviewer` when the orchestrator's prompt line says
`WIKI SWEEP:` — the end of Stage 7, after the code is committed and before
`espalier-pr.sh project` builds the espalier branch. Named on that prompt line;
not loaded otherwise. Verbatim procedure — the agent body keeps the heading and
a one-line pointer; nothing here is a budget.

## What This Is Not

This is not `/espalier-prune`. Prune re-derives a doc by re-spawning the
discovery scouts against the whole codebase and gates every file on a human
accept. This sweep reads ONE diff — the change that just passed review — and
asks a single question per doc: **does this diff make anything written here
false?** It never re-derives, never re-scouts, and never rewrites a doc in its
own voice. Drift the sweep cannot see from this diff is the doctor's job.

Nothing here is your opinion about the docs. A wiki paragraph you find thin,
a rule you would have worded differently, a section you think is missing — all
`NO-IMPACT` unless THIS diff falsified it.

## Inputs

- The change's code diff: `git diff <Base-Ref>..HEAD -- . ':(exclude)espalier/'`
- `espalier/wiki/*.md` — architecture, data-models, critical-paths, external-services
- `espalier/rules/*.md`

## Procedure

1. **Skip fast, and say so.** If the diff touches no source file — tests only,
   docs only, config only — every verdict is `NO-IMPACT` and you are done. Do
   not go looking for something to justify the call.

2. **Read the diff before the docs.** Build the list of what actually changed:
   modules added or removed, call paths rerouted, data shapes altered, external
   calls introduced or dropped, entry points moved. Then read each doc against
   that list. Reading the docs first invites you to pattern-match prose onto a
   diff that does not support it.

3. **Per file, one verdict.** For each wiki and rule file: `NO-IMPACT`, or a
   patch. A patch carries the smallest edit that makes the file true again —
   amend the sentence, add the row, extend the list. Keep the file's existing
   structure, headings, ordering and voice; a diff that reflows a section you
   are not correcting is a rewrite, not a sweep.

4. **Cite or drop it.** Every patch names the hunk that forces it —
   `file:line` from the DIFF, not from the doc. A claim you cannot anchor to a
   hunk does not go in, however true it looks. This is the whole bar: the sweep
   is trusted to commit without a human accept ONLY because every line it
   writes is traceable to reviewed code.

5. **Never delete.** Additive or amending only. A section the diff appears to
   retire is NOT removed — record it under `### Proposed Removals` and leave
   the file's text alone. A removal needs the full prune protocol and its
   Removed-rules ledger, because a silently dropped rule is unrecoverable and
   invisible. Retiring surface is `/espalier-simplify`'s lane, not this one.

6. **Rules are canon, and the bar is higher.** Edit `espalier/rules/` ONLY when
   the diff establishes a convention the rules do not yet state, or contradicts
   one they do. A rule file is not a changelog: a change that merely FOLLOWS an
   existing rule is `NO-IMPACT`. When you do patch a rule, say in the
   justification which rule bullet is now wrong and why the diff proves it — a
   rule edit routes the espalier PR to the rule owner (CODEOWNERS, Rule-canon
   gate in `espalier/rules/development-process.md`), so a speculative one costs
   a human their time.

7. **Silence is a correct answer, and the common one.** Most changes do not
   move architecture, data models, critical paths or external services. A sweep
   that finds something every run is miscalibrated, and the patches it writes
   are noise in a PR that a human is expected to trust.

## Output

```
### Wiki Sweep
- Diff scope: {N files, M hunks | no source files — skipped}
- wiki/architecture.md: {NO-IMPACT | PATCH — reason, citing file:line from the diff}
- wiki/data-models.md: {…}
- wiki/critical-paths.md: {…}
- wiki/external-services.md: {…}
- rules/{each file}: {NO-IMPACT | PATCH — which bullet is wrong, citing file:line}

### Proposed Removals
{one line per section the diff appears to retire — file, what, why — or `none`}
```

Append BOTH blocks — `### Wiki Sweep` and `### Proposed Removals` — to the
change's `espalier/changes/{type}/{slug}/doc-patches.md`, creating it if it is
not there. That file is the sweep's record: `delivery_brief` reads the
`### Wiki Sweep` block out of it for the brief's `## Doc Refresh` section, and
a removal that exists only in your reply is a removal nobody will ever action.
A sweep whose verdicts live only in the transcript leaves the human approving
at Stage 10 with no idea a doc was touched.

Then apply the patches you proposed — edit the files directly — and stop.
Committing them is Stage 7's job, not yours: the orchestrator calls
`espalier-pr.sh project` once for the wiki edits and once for the rule edits,
so each class lands as its own revertable commit on the espalier PR.
