# Mode: simplification

Read by `harness-coder` and `harness-reviewer` when requirements.md carries `simplify_from:` (the prompt says `SIMPLIFICATION CHANGE:`) — a cut filed by `/espalier-simplify`. Two sections: the coder's, then the reviewer's — read yours. Named on that prompt line by the orchestrator;
not loaded otherwise. Verbatim procedure — the agent body keeps the heading
and a one-line pointer; nothing here is a budget.

## Simplification Changes: Retire the Whole Obligation

When requirements.md carries `simplify_from:` frontmatter (a cut filed by
`/espalier-simplify`), the task is a DELETION with a proof record, and the
failure modes differ from a feature's: a half-removed surface, a consumer the
record missed, or complexity that merely moved. Read the
`## Simplification Evidence` and `## Retired Surface` sections first, then:

1. **Cut the whole boundary, from the outside in.** For every Retired
   Surface entry take the declaration; its registration / dispatch /
   parsing / compatibility paths; the implementations, adapters, state,
   caches, events, and cleanup behind it; its imports / exports / barrels
   and generated inventories; its config keys, env vars, and flags; its
   migrations, fixtures, examples, and doc sections; the tests dedicated to
   it; and any dependency or script that becomes unnecessary. Leave no
   stub, no `removed` comment, no dead re-export, no compat shim, and no
   "just in case" branch — a shim or migration path exists ONLY when the
   requirement names the consumer that needs it.
2. **Never relocate the complexity.** Two representations do not become one
   by adding a synchronization layer; a deleted wrapper does not come back
   as a helper two files over. If the cut needs machinery the record did
   not budget (`Net effect`), stop and report it — that is a survey error,
   not a coding problem.
3. **A consumer the record missed is a STOP, not a workaround.** If a
   search or a build / test failure reveals a live consumer — dynamic
   dispatch by string, a template, a config key, a scheduled job, a
   published export, persisted data — do not improvise a fallback or a
   partial delete. Report it under `- Missed consumer:` with `file:line`,
   leave the boundary consistent (fully cut or fully intact), and let the
   round FAIL back to the survey. The same holds on a `FIX ROUND` carrying
   a `[simplify-consumer]` / `[simplify-protected]` P0: either prove that
   consumer dead too and widen `## Retired Surface` under the same
   discipline, or restore the boundary fully — never patch a partial
   delete; the orchestrator aborts the change and the survey row becomes
   a LEAD carrying the fact.
4. **Run the residue search after the cut:** every retired name, string,
   path, key, and flag, repo-wide (`grep -rn`), excluding git history and
   CHANGELOG. Zero hits, or each remaining hit named with its reason.
5. **Keep the surviving contract proven.** Run the record's decisive check
   and the surviving contract's tests in the scoped test command (folded
   test-mode: they are this change's tests — add the one that would fail
   if the cut were wrong when none exists). Never weaken or delete a test
   to make the deletion pass; a test that only described the retired
   behavior is part of the cut and is listed as such.

Append to your coding report:

```
### Retired Surface
- Retired: {every entry from requirements.md — each marked done}
- Residue search: {command} — {0 hits | N hits: file:line — reason each}
- Surviving contract check: {test / probe run — result}
- Kept on purpose: {entry — the consumer that needs it | none}
- Missed consumer: {file:line — what reaches it | none}
```

A simplification change whose report lacks this block, or whose
`Missed consumer:` line is not `none`, is not complete — the reviewer files
it and the cut returns to the survey page.

## Simplification Review (when the change retires surface)

Run this after step 5 and before the Minimalism Review whenever the coding
report carries a `### Retired Surface` block or requirements.md carries
`simplify_from:` frontmatter — the change is a proved deletion filed by
`/espalier-simplify`, and the panel is the second, independent proof. Read
`## Retired Surface` in requirements.md, then:

1. **Re-search every retired name yourself, BEFORE reading the coder's
   residue search.** For each identifier, file, route, config key, env var,
   flag, event / protocol string, table / column, and fixture: search
   production code, tests, dynamic surfaces (string-keyed dispatch,
   reflection, registries, templates, config and env files, scheduled jobs,
   migrations, generated inventories), and external surfaces (published
   package exports, API routes, persisted formats, downstream consumers
   named in `espalier/wiki/external-services.md`). A live consumer the cut
   broke or left dangling is a **P0 `[simplify-consumer]`** with the exact
   `file:line` — the survey record was wrong, and the round FAILs however
   clean the diff looks. On the fix round that follows, only two outcomes
   pass: the boundary WIDENED with the consumer proved dead (re-search it
   yourself), or the boundary fully RESTORED; a partial delete that merely
   silences your `file:line` is the same P0 again.
2. **Boundary completeness.** A stub, a `removed` comment, a dead
   re-export, an orphaned fixture / test / doc section / config key, or a
   compat branch nothing reaches is a **P1 `[simplify-residue]`** naming
   the leftover.
3. **Relocation, not removal.** New synchronization glue, a re-grown
   helper, an adapter that preserves the retired policy — complexity moved
   rather than retired — is a **P1 `[simplify-relocate]`** when it
   contradicts the record's `Net effect`; a smaller instance is a `delete:`
   Minimalism note.
4. **Protected surface.** An authorization or ownership check, input-trust
   validation, data-loss guard, stored-format or migration compatibility
   path, or cleanup that establishes quiescence that the diff retires
   WITHOUT the requirement naming that consequence in its own words is a
   **P0 `[simplify-protected]`** — the security auditor files its own; you
   file yours.
5. **Proof present.** The record's decisive check and the surviving
   contract's tests are in the diff's test scope and pass; a deleted or
   weakened test on SURVIVING behavior is a **P1 `[simplify-proof]`** (a
   test that only described the retired behavior is part of the cut). A
   missing `### Retired Surface` block, or a `Missed consumer:` line other
   than `none`, is a P1 — the change is not complete.

Lead the Problem cell with the tag (`[simplify-consumer] …`): the round
snapshot keeps only the first 80 characters and `espalier-stats.sh` counts
these tags.

Independent means independent: run your own searches first and compare with
the coder's residue search afterwards; a search the coder ran that you cannot
reproduce is itself a finding. Findings use the normal table, count in the
sentinel like any P0 / P1, and the tie-break holds — nothing mandated by the
rules or specs is ever residue.
