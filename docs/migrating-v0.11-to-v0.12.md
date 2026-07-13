# Migrating from v0.11.0 to v0.12.0 (Grill Blind-Spot Pass)

## TL;DR

```bash
# 1. Update the plugin
/plugin update espalier-engineering

# 2. From inside Claude Code, in your target project:
/espalier-migrate
```

Or run the script directly:

```bash
# from the target project root
bash <plugin>/scripts/migrate-v0.11.0-to-v0.12.0.sh --dry-run   # preview
bash <plugin>/scripts/migrate-v0.11.0-to-v0.12.0.sh --yes
```

## What v0.12.0 changes — and why

Stage 1 grilling interrogates the *requirement text* for ambiguity and verifies
stated premises against the *code*. What it never did was consult the two
artifacts `/espalier-init` builds to describe your project: `espalier/rules/`
(your encoded conventions) and `espalier/wiki/` (the map of the system). So a
requirement that would **violate a documented convention** or **re-implement a
capability the wiki already documents** sailed through Stage 1 and was caught —
if at all — only at the Stage 4 review, a full rework round later.

v0.12.0 adds **Step 1.5, the blind-spot pass**. After scoring the text signals
and before the question loop, grill cross-references the requirement against
`espalier/rules/` + `espalier/wiki/` and looks for three collision classes:

- **Rule collision** — the approach contradicts a `rules/` convention (a `throw`
  where coding-standards mandates `Result<T>`).
- **Wiki duplication** — the requirement re-implements something `wiki/` already
  documents (a new HTTP client when `external-services.md` documents one).
- **Unstated ripple** — the requirement touches a documented critical-path or
  data-model whose downstream isn't in the requirement (a new field on an `Order`
  that `critical-paths.md` shows feeding three consumers).

Each **confirmed** collision becomes a Stage 1 question citing the exact
`rules/<file>#section` or `wiki/<file>#section`, and floors the tier so a crisp
requirement that nonetheless collides can't skip grilling. Before raising a
collision, grill **verifies the cited convention still holds in the code** — a
stale doc is flagged (`mark_stale`, the same signal `/espalier-doctor` and the
post-merge hook use), never raised as a false collision. It surfaces collisions
with conventions that already exist only — it never brainstorms new designs — and
it stays **silent when there is no map to collide with**, so behaviour is
unchanged on an input that has no `espalier/rules` or `espalier/wiki` to consult.

This is the project's own thesis — land inside your conventions on the first try —
applied to the requirement itself, one stage earlier than the reviewer.

### Known limitation

The collision fixtures in the eval harness inline their mock `rules/`/`wiki/`
context, which **under-measures** the real gain: a capable model reasons over any
context handed to it, so an A/B that pre-supplies the map erases the very
difference Step 1.5 makes. The fixtures are a capability + regression check, not a
clean causal isolation; a faithful A/B needs an on-disk `espalier/` fixture
project and is deferred. See `docs/grill-blindspot-crosscheck-plan.md` §5.1.

## What the migration script edits

The change is confined to **one** pure-copy pipeline file, so
`migrate-v0.11.0-to-v0.12.0.sh` does exactly one thing:

1. Backs up `espalier/skills/espalier-grill/SKILL.md` to
   `espalier/skills/espalier-grill/SKILL.md.pre-v0.12.bak` and refreshes it from
   the v0.12.0 template (which carries Step 1.5).
2. Runs a verification block — Step 1.5 present, cross-checks `espalier/rules/` +
   `espalier/wiki/`, keeps the `mark_stale` verify-before-raise rule, file
   non-empty — and exits non-zero if any check fails.

It refuses to run against a stale plugin whose grill template lacks Step 1.5
(rather than "migrating" you back to pre-v0.12 behaviour), and it is idempotent —
re-running detects Step 1.5 in the installed grill skill and no-ops. No `python3`
required.

The grill skill is plugin-owned (copied verbatim at init, never substituted with
project-specific values), so there is nothing customised to preserve — unlike the
push gate in v0.11.0, this migration has no "customised install" branch.

## Rollback

The one rewritten file is backed up next to itself:

```bash
cp espalier/skills/espalier-grill/SKILL.md.pre-v0.12.bak \
   espalier/skills/espalier-grill/SKILL.md
```

Delete the backup once you are satisfied.

## Non-breaking

No stage was added or removed; no state-file schema changed; `requirements.md`
gains an optional `## Convention Notes` block only when a cross-check actually ran.
Grill's behaviour is identical to v0.11.0 on any requirement with no `rules/`/
`wiki/` collision — Step 1.5 adds a question only when it finds and confirms one.
`--no-grill` and non-interactive runs are unaffected.
