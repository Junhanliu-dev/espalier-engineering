---
name: espalier-audit
description: Repo-wide security audit — inventory every trust-boundary defect in the EXISTING code (not a change diff), write the findings to espalier/wiki/security-audit.md, and optionally dispatch each finding into /espalier-fix. Read-only against source; never edits code.
---

# Espalier Audit

A standalone repo-wide security audit lane. The Stage 4 `harness-security` audit
is **change-scoped** — it sees only the diff a pipeline run produced, so a
trust-boundary hole that predates Espalier (or arrived outside the pipeline) is
never in its view. This lane closes that gap: it enumerates the project's whole
security surface, runs `harness-security` in **repo-audit mode** over it, and
writes a point-in-time findings inventory to `espalier/wiki/security-audit.md`.

It is NOT a pipeline. No stages, no gates, no `changes/` folder, no
`pipeline-state.md`, and **no hard-blocking** — findings are an inventory, not a
verdict on a change. Fixing a finding ALWAYS goes through `/espalier-fix`, which
gives each one its own diagnosis grill, approval gate, coder, review panel
(including a fresh security re-audit), and contracted abuse test. This skill
never edits source code and never spawns `harness-coder` directly.

## When to Use

- "/espalier-audit" or "/espalier-audit <path>"
- "Audit the whole repo for security issues"
- "Do we have any IDOR / price-tampering / mass-assignment holes today?"
- After adopting Espalier on a codebase that predates the security audit —
  the Stage 4 auditor only guards NEW changes; this baselines the old ones.

Do NOT use for:
- Reviewing a change in flight → the pipeline's Stage 4 panel already audits it.
- Fixing a known bug → `/espalier-fix <bug>` directly.
- A question ("is X endpoint safe?") → `/espalier-ask` first; audit if unsure.

## Trigger

```
/espalier-audit [scope-path]
```

Optional `scope-path` (e.g. `src/api`) restricts the audit to surfaces under
that path. Everything else is the full repo. No other flags.

## Preconditions

Requires an Espalier install with the v0.9.0 security artifacts:
`espalier/agents/harness-security.md` (with its `## Repo-Audit Mode` section)
and `espalier/rules/security-standards.md`. If either is missing, stop and tell
the user to run `/espalier-init` (fresh project) or `/espalier-migrate`
(pre-v0.9 install). Do not improvise an audit without the agent + rule.

## Procedure

### 1. Enumerate the security surface

Build the list of candidate surface files — request handlers, queue / event /
async consumers, authorization decisions, and persistent writes reachable from
client input:

1. Read `espalier/rules/security-standards.md` → the **Trust Boundary** section
   names this project's entry points (discovered at init).
2. Read `espalier/wiki/critical-paths.md` → entry points + primary flows.
3. Verify against the code: Glob/Grep for the named patterns. If the discovered
   sections are unfilled placeholders (a migrated install that never ran
   `/espalier-doctor`), fall back to a generic surface sweep — `routes/`,
   `handlers/`, `controllers/`, `consumers/`, `jobs/`, `api/`, HTTP-verb
   registrations, message-handler registrations — and say so in the report
   header. A queue/event consumer is ALWAYS a candidate surface: it receives
   external data exactly like an HTTP handler.
4. Apply the `scope-path` filter if given.

If the surface list is empty, write a report saying so (a static site has
nothing to audit) and stop — do not manufacture surfaces.

### 2. Spawn the auditor(s) in repo-audit mode

- **≤ 8 surface files** → ONE `harness-security` spawn covering all of them.
- **> 8** → group by directory into at most 4 batches and spawn them
  concurrently in ONE message. Auditors don't share state, so batches must not
  split a handler from the helpers it calls — group by feature directory, not
  alphabetically.

Spawn prompt (per batch):

```
Agent tool:
  prompt: |
    You are the harness-security auditor in REPO-AUDIT MODE.
    Read espalier/agents/harness-security.md and follow its
    "## Repo-Audit Mode" section — you are auditing EXISTING code, not a
    change; there is no coding-report.md and no changes/ dir.

    SURFACE FILES TO AUDIT (the code as it stands NOW):
    {file list, one per line}

    Trace every client-supplied value in these files to its authorization
    decision or persistence call, per espalier/rules/security-standards.md.
    Assume the client is hostile. Do NOT write security-record.md — return
    your findings as your final message in the exact Repo-Audit output
    format from your instruction file.
```

If an auditor returns nothing usable (empty / off-format), re-spawn that batch
once; a second failure is reported in the page header as an audit gap — never
silently dropped.

### 3. Consolidate and write the wiki page

Merge the batch results (dedupe a finding reported by two batches on the same
`file + field + defect`) and write — OVERWRITE, current state only —
`espalier/wiki/security-audit.md`:

```markdown
# Security Audit — {project}

> Point-in-time repo-wide trust-boundary audit, generated by `/espalier-audit`.
> Re-run the skill to refresh; do NOT `/espalier-prune` this page (it has no
> scout source — it is regenerated, not refreshed). Not drift-tracked.

- **Date:** {YYYY-MM-DD}
- **Commit:** {git rev-parse --short HEAD}
- **Scope:** {scope-path or "full repo"}
- **Surfaces audited:** {N files across M batches}
- **Result:** {X} P0 · {Y} P1 · {Z} P2/P3 — or CLEAN

## Findings
| # | Priority | File | Field / Endpoint | Trusted-from-client defect | Fix | Status |
|---|----------|------|------------------|----------------------------|-----|--------|
| 1 | P0 | src/order.controller.js:12 | orderId / GET /orders/:id | loaded by client id, no owner check (IDOR) | owner-scoped query | OPEN |

## Abuse-Test Contracts (one per finding — feed these to /espalier-fix)
{the auditor's Security-Sensitive Fields blocks, verbatim}

## Controls Confirmed
{endpoints whose controls the auditor verified present, with file:line}

## Surfaces With No Sensitive Fields
{audited files that turned out to carry no sensitive client input}
```

The `Status` column starts `OPEN` for every finding; when a finding is
dispatched to the fix lane (step 4), rewrite its cell to the fix's change slug
(`fix/{slug}`). If a dispatched lane ends `ABORTED` or `PARTIAL_FIX`, set the
cell to `DISPATCH_ABORTED(fix/{slug})`. A later audit run preserves rather
than overwrites non-`OPEN` cells (`fix/{slug}` and `DISPATCH_ABORTED(...)`
carry history the fresh scan cannot re-derive). This page is the only artifact
this skill writes to the wiki.

After writing/updating the page, commit it immediately (`git add
espalier/wiki/security-audit.md && git commit -m 'docs(espalier): security
audit {date}'`) — dispatched fix lanes require a clean tree at Stage 7 and
must not sweep this page into their own commit.

### 4. Offer the fix handoff (interactive only)

Decide interactivity with the explicit-signal helper — NEVER a bash TTY test
(stdin has no TTY inside Claude Code even with the user right there; a TTY
test would silently skip this handoff on every interactive run):

```bash
. espalier/hooks/drift-helpers.sh
interactivity_mode        # -> "interactive" | "unattended"
```

If there are P0/P1 findings AND the run is interactive, ask ONE
`AskUserQuestion` (multiSelect) listing each P0/P1 as an option — label
`{priority} {file}: {short defect}` — plus the implied "none for now" via
selecting nothing. For EACH selected finding, run the fix lane **sequentially**
(each fix is its own change with its own approval gate — never batch them into
one):

```
/espalier-fix {priority} trust-boundary defect in {file}: {defect}. Required
control: {required_control}. Abuse test: {abuse_test}. (Source:
espalier/wiki/security-audit.md finding #{n}.)
```

Then update that finding's `Status` cell as above (a lane that ends `ABORTED`
or `PARTIAL_FIX` gets `DISPATCH_ABORTED(fix/{slug})`), and commit the page
immediately after each status edit (`git add espalier/wiki/security-audit.md
&& git commit -m 'docs(espalier): security audit {date}'`) so the next
dispatched lane starts from a clean tree. The fix lane's Stage 0 causal-link
discovery may find no causing change for a pre-existing hole — that is
expected; the lane proceeds without a link.

Only an EXPLICITLY unattended run (`CI` / `ESPALIER_UNATTENDED` /
`ESPALIER_LOOP` / `ESPALIER_HEADLESS` set → `interactivity_mode` returns
`unattended`) skips the prompt — the same convention as the grill and the
approval gates: write the page, print its path and the P0/P1 counts, done.
If you (the orchestrator) can call `AskUserQuestion`, you ARE interactive
and MUST offer the handoff.

### 5. Byproduct: flag a stale trust-boundary doc (notify-only)

If the audit contradicts the **discovered** sections of
`espalier/rules/security-standards.md` (e.g. the rule names an ownership
helper the code no longer uses, or entry points that don't exist), flag it via
the standard drift sidecar — do NOT edit the rule:

```bash
. espalier/hooks/drift-helpers.sh
mark_stale "espalier/rules/security-standards.md" "$(git rev-parse HEAD)" "audit-verify: <one-line mismatch>"
```

and surface one line pointing at `/espalier-prune espalier/rules/security-standards.md`.

## Cost

LIGHT-MEDIUM — 1-4 read-only auditor sub-agents plus one wiki Write. Scales
with the surface count, not repo size; use `scope-path` to bound it on a large
codebase.

## What This Skill Does NOT Do

- Never edits source code, and never spawns `harness-coder` — every fix goes
  through `/espalier-fix` with its own approval gate and review panel.
- Never blocks anything. No gate reads this page; it is an inventory. (The
  Stage 4 panel remains the enforcement point for changes.)
- Never appends history — the page is OVERWRITTEN per run; git history holds
  prior audits.
- Never edits `security-standards.md` or any rule/wiki/spec — staleness is
  flagged notify-only (step 5); refresh is `/espalier-prune`.
- Never audits a diff — that is the pipeline's Stage 4. This lane audits the
  repo as it stands.
