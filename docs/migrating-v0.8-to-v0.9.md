# Migrating from v0.8.x to v0.9.0 (Security Audit)

If your project has an `espalier/` directory bootstrapped with Espalier v0.8.x, this guide upgrades it to v0.9.0 — the security audit. The upgrade is additive and mechanical (one script); this doc tells you what changes and what to verify.

## TL;DR

```text
# 1. Update the plugin
/plugin update espalier-engineering

# 2. From inside Claude Code, in your target project:
/espalier-migrate
```

`/espalier-migrate` auto-detects your install version. A v0.8.2 install needs only the v0.8.2→v0.9.0 step. (An older install gets the rest of the chain — up to … v0.8 → v0.8.1 → v0.8.2 → v0.9.0 — applied in order.) It shows a dry-run preview, asks before applying, and runs verification.

To run the script directly instead:

```bash
# from the target project root
bash <plugin>/scripts/migrate-v0.8.2-to-v0.9.0.sh --dry-run   # preview
bash <plugin>/scripts/migrate-v0.8.2-to-v0.9.0.sh             # apply (prompts)
```

## What v0.9.0 changes

Before v0.9, Stage 4 (code review) ran one agent — `harness-reviewer` — checking correctness and conventions. Security was not a first-class concern: an endpoint that trusted a client-supplied `price`, or loaded an object by a client-supplied `orderId` with no ownership check, could pass review.

v0.9 adds a **security audit** to Stage 4. It now runs a **two-agent panel**:

- **`harness-reviewer`** — correctness / conventions (unchanged).
- **`harness-security`** (new) — the trust boundary, on one axiom: *never trust data the frontend sent.*

The auditor traces each client-supplied value to where it reaches an authorization decision or a persistent write, classifies it on five risk axes — **money** (price, amount, balance, stock), **identity** (userId, accountId), **permission** (role, isAdmin, scope), **owner** (orderId, tenantId), **state** (status, approved) — and hard-blocks any sensitive field the backend fails to re-derive, re-authorize, or recompute. This catches the IDOR / BOLA, price-tampering, mass-assignment, and illegal-state-transition classes.

### What lands in your install

- **New always-loaded rule** `espalier/rules/security-standards.md` — the trust-boundary doctrine + the sensitive-field taxonomy. `harness-coder` reads it while writing, so security shifts left.
- **New agent** `espalier/agents/harness-security.md` — the auditor (Read / Grep / Glob / Bash — no Write/Edit, fresh eyes).
- **New skill** `espalier/skills/espalier-security/SKILL.md` — the audit checklist + abuse-test recipe.
- **Stage 4 → a panel** in `pipeline.md` and the `espalier` / `espalier-fix` skills: any P0 from either agent loops the coder; the `Reviewed-Diff` push certificate is written only when both are clean.
- **Abuse tests are enforced.** For every sensitive field the auditor flags, Stage 5 must write a negative test (tamper → rejected → store unchanged) and Stage 6 blocks if one is missing.
- **Coder / reviewer / testing** gain security sections; the **push gate** gains a secret scan (blocks) + a dependency audit (warns), both degrading gracefully when tooling is absent.
- **New lane** `/espalier-audit` (`espalier/skills/espalier-audit/`) — the Stage 4 audit only sees new changes; this runs the same auditor repo-wide over your **existing** code (a `## Repo-Audit Mode` section in the agent), writes the findings inventory to `espalier/wiki/security-audit.md`, and hands each selected P0/P1 to `/espalier-fix`. CLAUDE.md and `espalier/agent.md` are patched to mention it.

### Production hardening (same release)

v0.9.0 also raises the bar on the code the pipeline *generates* and fixes a set of gate defects:

- **New always-loaded rule** `espalier/rules/production-standards.md` — resilience (timeouts, bounded queries, atomic state), observability (structured logs, no swallowed errors), data-safety (expand→migrate→contract, idempotent consumers). The reviewer enforces it at tiered severity: **P0** for the data-loss class (destructive migration, unbounded write, swallowed error on a money/state path — hard-blocks the loop), **P1** for readiness gaps (missing timeout/log/pagination/idempotency). The coder reads it at write-time; new external calls require a failure-mode test.
- **Fail-closed push gate** — the gate now runs from the repo root (wrapper + gate both `cd`), closing a hole where a `git push` from a subdirectory skipped the stage / review-certificate / secret checks and allowed the push.
- **Programmatic Stage 3 gate** — the orchestrator re-runs build + lint itself before the review panel; the coder's self-reported status is no longer the gate.
- **Per-round `VERDICT:` sentinels** — the reviewer and security records end with a machine-greppable verdict line and are overwritten per round, closing a stale-verdict certification path.
- **Human-gate fix** — the grill and requirements-approval gates now key off an explicit `interactivity_mode` signal, not a bash TTY test (which reads "non-interactive" inside Claude Code and silently auto-approved).
- **Deploy-aware Stage 9** — verifies a real deploy when init discovers one, records a clean `SKIPPED: no-deploy-config` when it doesn't.

To fill the `{discovered}` cells of `production-standards.md` (your project's own timeout wrapper, logger, migration tool), run `/espalier-doctor` or edit the file — the universal seeds bind immediately either way.

## What to verify after upgrading

The migration's own verification prints `X passed, Y failed`. You can also spot-check:

```bash
# the three new files exist and are symlinked
ls -l .claude/rules/espalier-security.md .claude/agents/harness-security.md .claude/skills/espalier-security

# the Stage 4 panel is wired
grep -c "review panel" espalier/pipeline.md
grep -c "harness-security" espalier/skills/espalier/SKILL.md

# the repo-wide audit lane is wired
ls -l .claude/skills/espalier-audit
grep -c "## Repo-Audit Mode" espalier/agents/harness-security.md
```

## One manual step

The migration cannot fill the `{discovered}` sections of `security-standards.md` — the trust boundary (your entry points, how identity / ownership / validation are done) and your project-specific sensitive field names. The **universal taxonomy and controls are live immediately**; to fill the discovered parts, run `/espalier-doctor` (it re-scouts) or edit the file by hand.

## Recommended after upgrading

Run `/espalier-audit` once. The Stage 4 audit protects changes from here on — the baseline audit inventories the trust-boundary holes already in the codebase (to `espalier/wiki/security-audit.md`) so you can burn them down through `/espalier-fix`.

## Rollback

Every migration is idempotent and backs up any customised pure-copy pipeline file to `<file>.pre-v0.9.0.bak`. To undo, `git checkout` the changed files (or restore from the `.bak`) and remove the three new files plus their `.claude/` symlinks.

## Non-breaking

New pipeline runs get the audit. The auditor **self-noops** on changes with no security-sensitive surface (a CSS tweak, a copy change), so the cost lands only where it matters. In-flight changes are unaffected.
