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

## What to verify after upgrading

The migration's own verification prints `X passed, Y failed`. You can also spot-check:

```bash
# the three new files exist and are symlinked
ls -l .claude/rules/espalier-security.md .claude/agents/harness-security.md .claude/skills/espalier-security

# the Stage 4 panel is wired
grep -c "review panel" espalier/pipeline.md
grep -c "harness-security" espalier/skills/espalier/SKILL.md
```

## One manual step

The migration cannot fill the `{discovered}` sections of `security-standards.md` — the trust boundary (your entry points, how identity / ownership / validation are done) and your project-specific sensitive field names. The **universal taxonomy and controls are live immediately**; to fill the discovered parts, run `/espalier-doctor` (it re-scouts) or edit the file by hand.

## Rollback

Every migration is idempotent and backs up any customised pure-copy pipeline file to `<file>.pre-v0.9.0.bak`. To undo, `git checkout` the changed files (or restore from the `.bak`) and remove the three new files plus their `.claude/` symlinks.

## Non-breaking

New pipeline runs get the audit. The auditor **self-noops** on changes with no security-sensitive surface (a CSS tweak, a copy change), so the cost lands only where it matters. In-flight changes are unaffected.
