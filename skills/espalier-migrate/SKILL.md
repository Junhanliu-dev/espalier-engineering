---
name: espalier-migrate
description: Migrate an existing harness/espalier install to the current Espalier version — auto-detects which of v0.1→v0.2, v0.3→v0.4, v0.4→v0.5, the v0.5.3 coder-agent patch, v0.5→v0.6 (Stage 1 grill), v0.6→v0.7 (read-only /espalier-ask lane), v0.7→v0.8 (requirements approval gate), the v0.8.1 impact-analysis agent patch, the v0.8.2 re-review fixpoint loop, the v0.9.0 security audit, the v0.9.1 configurable escalation caps, the v0.9.2 correctness patch, the v0.9.3 skill-clarity patch, the v0.9.4 security-skill patch, the v0.9.6→v0.10.0 push-gate reshape, the v0.10.0→v0.11.0 hook exit-code release, the v0.11.0→v0.12.0 grill blind-spot pass (Stage 1 rules/wiki cross-check), the v0.12.0→v0.13.0 minimalism release (coder Solution Selection Ladder + reviewer advisory Minimalism Review), the v0.13.0→v0.13.1 polish patch (stage-conditional coding guidance + reviewer step-7 abuse-test duty + code-review gate line), the v0.13.1→v0.13.2 readability release (coder clarity-then-brevity tie-break + comment-convention discovery + reviewer advisory Readability Review with the cryptic-public-name P1), the v0.13.2→v0.14.0 Codex platform release (platform-neutral hook wrappers + optional .agents/skills + AGENTS.md + .codex wiring), the v0.14.0→v0.15.0 Copilot platform release (camelCase hook adapter + optional .github/skills + copilot-instructions + .github/agents + .github/hooks wiring), the v0.15.0→v0.16.0 multi-dev maintenance floor (conv_fold conventions reader + maintenance lanes + canonical-ref keys + .gitattributes union entry + optional CODEOWNERS), and the v0.16.0→v0.17.0 B-team release (weekly gardener rota + tracked single-line .doctor-stamp with clean/dirty semantics + conventions file-per-key) you need and applies them in order.
---

# Espalier Migration Runner

## When to Use
- "Migrate to Espalier" / "Upgrade my Espalier install"
- "Upgrade my harness to the latest version"
- "Rename harness/ to espalier/"
- "/espalier-migrate"

## When NOT to Use
- Fresh project with no existing `harness/` or `espalier/` dir → use `/espalier-init` instead.
- Already fully up to date — `/espalier-migrate` detects this itself and exits cleanly with no changes.

## Instructions

You are running a migration of an existing install to the current Espalier
version. Up to TWENTY-FOUR migrations may apply, always in this order:

1. **v0.1.x → v0.2.x** — typed `harness/changes/{type}/{slug}/` layout,
   `/harness-fix` lane, squash-merge decision. Mechanical:
   `scripts/migrate-v0.1-to-v0.2.sh`.
2. **v0.3.x → v0.4.0** — `harness/` → `espalier/` directory + skill rename
   (`harness-run` → `espalier`, `harness-{coding,…}` → `espalier-*`).
   Mechanical: `scripts/migrate-v0.3-to-v0.4.sh`.
3. **v0.4.x → v0.5.0** — doc-drift detection: drift hooks, the
   `/espalier-prune` + `/espalier-doctor` skills, the post-merge dispatcher,
   `.doctor-cadence`. Mechanical: `scripts/migrate-v0.4-to-v0.5.sh`.
4. **v0.5.0–v0.5.2 → v0.5.3** — appends the `## Editing Discipline` section to
   the coder sub-agent (`espalier/agents/harness-coder.md`). Mechanical:
   `scripts/migrate-v0.5.2-to-v0.5.3.sh`.
5. **v0.5.x → v0.6.0** — Stage 1 grilling: installs the `espalier-grill` skill,
   refreshes the four changed pipeline templates (which also date-prefix change
   folders). Mechanical: `scripts/migrate-v0.5-to-v0.6.sh`.
6. **v0.6.x → v0.7.0** — read-only ask lane: installs the `espalier-ask` skill,
   patches CLAUDE.md + `espalier/agent.md` to mention `/espalier-ask`. Purely
   additive — no pipeline change. Mechanical: `scripts/migrate-v0.6-to-v0.7.sh`.
7. **v0.7.x → v0.8.0** — requirements approval gate: refreshes the three changed
   pipeline templates (`pipeline.md`, `espalier`, `espalier-fix`) so both
   pipelines STOP for explicit user sign-off after the requirement is written +
   reviewed, before any code is written (no-TTY runs auto-approve). Mechanical:
   `scripts/migrate-v0.7-to-v0.8.sh`.
8. **v0.8.0 → v0.8.1** — impact-analysis agent patch: appends a
   `## Change Impact Analysis` section to the coder sub-agent
   (`espalier/agents/harness-coder.md`) and a `## Runtime-Surface Review` section
   to the reviewer sub-agent (`espalier/agents/harness-reviewer.md`). Both make
   the agents reason about every surface a change touches (admin UIs, API
   validation, client forms, persisted data, other callers) — not just the
   programmatic happy path — so a now-derived value left user-required on a UI is
   caught at coding/review instead of returning as a fix round. Mechanical:
   `scripts/migrate-v0.8-to-v0.8.1.sh`.
9. **v0.8.1 → v0.8.2** — re-review fixpoint loop + push-gate certificate: code
   review becomes a loop — every coder fix is re-reviewed until a fresh review of
   the current code returns zero P0 — and the push gate blocks unless the pushed
   code matches the fingerprint the last review saw. Refreshes the two pure-copy
   pipeline files (`pipeline.md`, `espalier-fix`), appends a `## Re-review Rounds`
   section to `harness-reviewer.md`, and inserts the certificate check into
   `pre-push-gate.sh`. Mechanical: `scripts/migrate-v0.8.1-to-v0.8.2.sh`.
10. **v0.8.2 → v0.9.0** — security audit + production hardening (one release):
   a new `harness-security` agent joins Stage 4 as a review panel; a
   `security-standards` rule + `espalier-security` skill are added, and the
   coder/reviewer/testing/push-gate gain security sections. Ships
   `/espalier-audit`, the repo-wide audit lane (`espalier-audit` skill + a
   Repo-Audit Mode section). Adds an always-loaded `production-standards` rule
   (resilience / observability / data-safety, tiered severity) the coder writes
   to and the reviewer enforces; per-round `VERDICT:` sentinels + dual-record
   freshness; a fail-closed push gate (cwd guard) + programmatic build/lint gate;
   a deploy-aware Stage 9; the TTY→explicit-signal gate fix; and a single shipped
   `scout-prompts` file for prune/doctor. Creates the new per-project files,
   `bootstrap --force` refreshes the pure-copy pipeline/grill/hooks + copies
   scout-prompts + symlinks both new rules + runs the 37-check validation, and
   surgical appends patch the per-project files. Mechanical:
   `scripts/migrate-v0.8.2-to-v0.9.0.sh`.
11. **v0.9.0 → v0.9.1** — configurable escalation caps: the review-round +
   rollback hard stops move from hardcoded prose into a tracked
   `espalier/.espalier-config` (`max-req-rounds`, `max-code-rounds`,
   `max-test-rounds`, `max-rollbacks` — all default 3) the orchestrator reads at
   runtime. Creates the config file if absent (preserved on re-run) and refreshes
   the three pure-copy pipeline files (`pipeline.md`,
   `espalier/skills/espalier/SKILL.md`, `espalier-fix`) so their prose reads the
   config; a customised file is backed up to `<file>.pre-v0.9.1.bak`. Mechanical:
   `scripts/migrate-v0.9.0-to-v0.9.1.sh`.
12. **v0.9.1 → v0.9.2** — correctness patch: the fix lane's late-escalation
   gates detect via a marker line (the old text called a shell helper that was
   never shipped), its back-link reads the real `# Bug:` title, and its
   regression verification is scoped + dep-linked (no more false `true` from a
   suite that couldn't run); `/espalier-audit`'s fix handoff and
   `/espalier-prune`'s unattended path key off `interactivity_mode`; the push
   gate gates the ACTIVE change (completed changes stop blocking later manual
   pushes) and parses mocha/rspec/go test counts, preserving the substituted
   test command; scout 1.11 ships in `.scout-prompts.md` and prune/doctor map
   the security/production rules. Backs up customised pure-copy files to
   `<file>.pre-v0.9.2.bak`. Mechanical: `scripts/migrate-v0.9.1-to-v0.9.2.sh`.
13. **v0.9.2 → v0.9.3** — skill-clarity patch; no new lane, no new stage, no
   behaviour change to any gate or verdict. `espalier-grill` (pure-copy) gains an
   explicit user tier-override, a coverage guard so every counted ambiguity signal
   ends resolved / scoped-out / recorded in `## Open Questions`, and records a
   non-answer with a named safe default instead of dropping it. `espalier-review`
   (substituted) gets its two review loops rewritten as an explicit
   when / input / do / output / who workflow, stops restating severities in the
   production-readiness checklist (`production-standards.md` is the single source),
   and gains when-to-use + trigger phrases in its frontmatter. Backs both skills up
   to `<file>.pre-v0.9.3.bak`. Mechanical: `scripts/migrate-v0.9.2-to-v0.9.3.sh`.
14. **v0.9.3 → v0.9.4** — security-skill patch; no new lane, no new stage, no
   behaviour change to any gate or verdict (the security auditor's catch /
   false-positive rates are unchanged). The per-project `harness-security` AGENT
   and `espalier-security` SKILL gain when-to-use + the five sensitive axes as
   frontmatter trigger context, and the agent's P0 rubric and repo-audit
   "findings do not block" delta stop restating each other's semantics,
   cross-referencing one source instead. Both are per-project files that
   `bootstrap --force` never re-copies, so v0.9.4 shipped these template
   improvements with no way to reach an existing install. Frontmatter is edited
   LINE-WISE (an `inherit` tools-mode install has had its `tools:` line stripped;
   re-copying the template's frontmatter would reintroduce it). A body span the
   project has customised is left alone and reported warn-only. Backs both up to
   `<file>.pre-v0.9.4.bak`. Mechanical: `scripts/migrate-v0.9.3-to-v0.9.4.sh`.
15. **v0.9.6 → v0.10.0** — push-gate reshape. `{build_command}` / `{lint_command}` /
   `{test_command}` are now substituted into FUNCTION BODIES (`run_build` /
   `run_lint` / `run_tests`), so a value may be a single command OR a multi-line
   block — a repo that must run several suites (one per container in a Docker-first
   stack, one per workspace in a monorepo) can finally be expressed. Before,
   `{test_command}` landed inside a command substitution and had to be one
   expression. Build and lint also stop discarding stderr: the old template ran
   `<cmd> 2>/dev/null` and, on failure, printed `BLOCKED: Build fails` and nothing
   else; output is now captured and its tail printed. The migration rewrites those
   three spans in the installed gate, PRESERVING the commands substituted at init,
   and handles each span independently (a gate half-migrated by running the v0.9.2
   step against a v0.10.0 plugin has `run_tests` but old build/lint). A gate
   customised at init past the template shape is left completely untouched and
   reported, never mangled. Backs up to `<file>.pre-v0.10.0.bak`. Mechanical:
   `scripts/migrate-v0.9.6-to-v0.10.0.sh`.
16. **v0.10.0 → v0.11.0** — hook exit-code release. Claude Code PreToolUse /
   PostToolUse hooks block ONLY on exit code 2 with the message on stderr —
   exit 1 + stdout is a silent no-op, so the old push gate never actually
   blocked. Rebuilds the gate from the v0.11.0 template preserving the three
   substituted command bodies (customised gates: skip marker + manual
   contract), refreshes both wrappers (fail-closed python probe, broader push
   match), patches `check-layer-boundaries.sh` to exit 2 + stderr, gives the
   reviewer/security agents their record-file Write tool, and refreshes
   `pipeline.md` + the pure-copy pipeline skills so the Stage 4/6 gates read
   the verdict WORD (`FAIL`/`ESCALATION_REQUIRED` no longer advance as PASS),
   plus `espalier-review`/`espalier-security` with `{project}` re-substitution.
   Backs up to `<file>.pre-v0.11.bak`. Mechanical:
   `scripts/migrate-v0.10.0-to-v0.11.0.sh`.
17. **v0.11.0 → v0.12.0** — grill blind-spot pass. Stage 1 grilling now
   cross-references the requirement against the project's own `espalier/rules/`
   and `espalier/wiki/`, not just the requirement text: a new Step 1.5 surfaces a
   collision — an approach that violates an encoded rule (`throw` where the repo
   standardised on `Result<T>`), a capability the wiki already documents, an
   unstated downstream ripple — as a Stage 1 question citing the exact
   `rules/<file>#section`, and floors the tier so a crisp-but-colliding
   requirement can't skip grilling. It verifies each doc claim against the code
   first — a stale doc is flagged (`mark_stale`), never raised as a false
   collision — and stays silent when there is no map to collide with. The change
   is confined to one pure-copy file, so the migration is a single backup-and-
   refresh of `espalier/skills/espalier-grill/SKILL.md`. Backs up to
   `<file>.pre-v0.12.bak`. Mechanical: `scripts/migrate-v0.11.0-to-v0.12.0.sh`.
18. **v0.12.0 → v0.13.0** — convention-bounded minimalism. The coder gains a
   Solution Selection Ladder (conventions first, correctness within them,
   brevity only breaks ties: reuse what the project has → the convention-named
   mechanism → stdlib/native/installed dep → leanest compliant implementation;
   a NEW dependency needs a requirements.md line). The reviewer gains an
   advisory Minimalism Review (`delete:`/`stdlib:`/`native:`/`yagni:` findings
   capped at P2/P3 so they never re-open the Stage 4 fixpoint loop; ONE P1
   exception: a new dependency covering what stdlib / a native feature / an
   installed dep provides), binds the sentinel's `p1=` to the P1 row count,
   and restores the fan-out P1 bullet that had drifted from
   production-standards.md. All four touched files are per-project
   (substituted/scout-filled), so the migration is SURGICAL — anchored section
   inserts, never a template overwrite. Backs up to `<file>.pre-v0.13.bak`.
   Mechanical: `scripts/migrate-v0.12.0-to-v0.13.0.sh`.
19. **v0.13.0 → v0.13.1** — minimalism polish patch; no gate math, sentinel
   vocabulary, round-cap, or review-dimension change. The coding skill gains
   `## How This Skill Applies by Stage` (Stage 3 / Stage 5 testing / fix
   rounds — including fix-round findings-only scope and "a test-only
   dependency is still a NEW dependency"), the reviewer's Review Process gains
   the Stage 6 abuse-test check as numbered step 7 (explicitly skipped on
   code-review rounds; "Produce findings" renumbers to 8), and the review
   skill's code-review loop gains the Gate line its plan-review loop got in
   v0.13.0 (PASS/PASS_WITH_FIXES with p0=0 p1=0; rounds owned by Stage 4
   `max-code-rounds`). All three touched files are per-project — surgical
   anchored inserts, the By-Stage body extracted from the plugin template at
   runtime. Backs up to `<file>.pre-v0.13.1.bak`. Mechanical:
   `scripts/migrate-v0.13.0-to-v0.13.1.sh`.
20. **v0.13.1 → v0.13.2** — readability release: "human readable" stops being
   an accident of discovered conventions and becomes an explicit duty on both
   agents. The coder's ladder tie-break becomes clarity then brevity (same
   correctness → the more readable → only then the shorter); coding-standards
   gains a naming-intent floor ("a name STATES what it holds or does") and a
   `## Comments & Docstrings` section (scout 1.3 now discovers comment
   conventions); the reviewer gains an advisory Readability Review
   (`naming:`/`nesting:`/`magic:`/`comments:` findings capped at P2/P3, judged
   against the project's own conventions never taste; ONE P1 exception: a
   cryptic EXPORTED/public name — public names freeze into contracts callers
   bind to), with the sentinel's `p1=` counting that P1 like any other. All
   six touched files are per-project — surgical anchored splices (requires
   python3), the refreshed spans extracted from the plugin templates at
   runtime. The new coding-standards sections carry `{observed ...}`
   placeholders until `/espalier-prune` re-scouts. Backs up to
   `<file>.pre-v0.13.2.bak`. Mechanical:
   `scripts/migrate-v0.13.1-to-v0.13.2.sh`.
21. **v0.13.2 → v0.14.0** — Codex platform release. Always: refreshes the two
   plugin-owned hook wrappers (`post-edit-wrapper.sh` now parses Codex
   apply_patch input and resolves the repo root without
   `$CLAUDE_PROJECT_DIR`; `pre-push-gate-wrapper.sh` now joins argv-array
   commands before the git-push match — both inert on Claude Code). Optional
   (`--with-codex`, asked in Step 4b): wires the codex platform additively —
   `.agents/skills/` symlinks, `AGENTS.md` Espalier section + platform
   mapping, `.codex/config.toml` hook block, `.codex/agents/harness-*.toml`
   sub-agents, `espalier/.platforms`. Never unwires claude. Backs up to
   `<wrapper>.pre-v0.14.bak`. Mechanical:
   `scripts/migrate-v0.13.2-to-v0.14.0.sh`.
22. **v0.14.0 → v0.15.0** — Copilot platform release. Always: installs the new
   plugin-owned Copilot hook shim `espalier/hooks/copilot-hook-adapter.sh`
   (translates Copilot's camelCase `toolName`/`toolArgs` payload into the
   Claude/Codex `tool_name`/`tool_input` shape and dispatches to the shared
   wrappers; exit codes pass through — Copilot treats non-zero `preToolUse`
   exits as DENY). Optional (`--with-copilot`, asked in Step 4c): wires the
   copilot platform additively — `.github/skills/` symlinks,
   `.github/copilot-instructions.md` Espalier section,
   `.github/agents/harness-*.agent.md` custom agents,
   `.github/hooks/espalier-gates.json`. Never unwires claude/codex. New file
   only — no backups needed. Mechanical:
   `scripts/migrate-v0.14.0-to-v0.15.0.sh`.
23. **v0.15.0 → v0.16.0** — multi-dev maintenance floor (Release A). Always:
   refreshes the pure-copy pipeline files + `drift-helpers.sh` (the
   `conv_fold`/`conv_observations` conventions reader, per-mechanism
   maintenance lanes, promotion race guard, unattended Stage 0 continuation,
   conflict + slug-collision recipes) with backup-on-diff
   (`<file>.pre-v0.16.bak`); surgically appends the `## Maintenance Commits`
   section to the per-project `espalier/rules/development-process.md`; then
   `bootstrap --wire-only` appends the `.gitattributes` union entry for
   `espalier/.ask-gaps.tsv`, the `canonical-remote`/`canonical-branch` config
   keys, and runs the 48/53/58-check validation (side-effect: settings.json
   backup). Optional: `--codeowners-rules`/`--codeowners-wiki` (asked in
   Step 4d) write the CODEOWNERS marker block. Mechanical:
   `scripts/migrate-v0.15.0-to-v0.16.0.sh`.
24. **v0.16.0 → v0.17.0** — multi-dev maintenance B-team. Pure-copy only:
   refreshes `pipeline.md`, the espalier / espalier-fix / espalier-prune /
   espalier-doctor SKILL files, and `drift-helpers.sh` (doctor_due v2 with
   clean/dirty shared-stamp semantics + skew rejection, `doctor_stamp_shared`,
   `conv_slug`, per-key `append_convention`) with backup-on-diff
   (`<file>.pre-v0.17.bak`). No config change, no attribute change, no data
   migration — `espalier/conventions/` and `espalier/.doctor-stamp` appear on
   first write; the legacy `.conventions.tsv` is read forever, written never.
   Run-time assert: `.doctor-stamp` must not be gitignored. Mechanical:
   `scripts/migrate-v0.16.0-to-v0.17.0.sh`.

Your job: detect which one(s) apply, locate the scripts, preview, get
confirmation, apply in order. A v0.1.x install needs ALL TWENTY-THREE; a v0.3.x
install needs the last twenty-two; a v0.4.x install needs the last twenty-one; a
v0.5.0–v0.5.2 install needs the v0.5.3 patch then v0.6 … v0.16.0; a
v0.5.3–v0.5.x install needs v0.6 … v0.16.0; a v0.6.x install needs
v0.7 … v0.16.0; a v0.7.x install needs v0.8 … v0.16.0; a v0.8.0 install needs
v0.8.1 … v0.16.0; a v0.8.1 install needs v0.8.2 … v0.16.0; a v0.8.2 install
needs v0.9.0 … v0.16.0; a v0.9.0 install needs v0.9.1 … v0.16.0; a v0.9.1
install needs v0.9.2 … v0.16.0; a v0.9.2 install needs v0.9.3, v0.9.4,
v0.10.0, v0.11.0, v0.12.0, v0.13.0, v0.13.1, v0.13.2, v0.14.0, v0.15.0, then v0.16.0; a v0.9.3 install
needs v0.9.4, v0.10.0, v0.11.0, v0.12.0, v0.13.0, v0.13.1, v0.13.2, v0.14.0, v0.15.0, then v0.16.0; a
v0.9.4, v0.9.5, or v0.9.6 install needs v0.10.0, v0.11.0, v0.12.0, v0.13.0,
v0.13.1, v0.13.2, v0.14.0, v0.15.0, then v0.16.0; a v0.10.0 install needs v0.11.0, v0.12.0, v0.13.0,
v0.13.1, v0.13.2, v0.14.0, v0.15.0, then v0.16.0; a v0.11.0 install needs v0.12.0, v0.13.0, v0.13.1,
v0.13.2, v0.14.0, v0.15.0, then v0.16.0; a v0.12.0 install needs v0.13.0, v0.13.1, v0.13.2, v0.14.0, v0.15.0,
then v0.16.0; a v0.13.0 install needs v0.13.1, v0.13.2, v0.14.0, v0.15.0, then v0.16.0; a v0.13.1
install needs v0.13.2, v0.14.0, v0.15.0, then v0.16.0; a v0.13.2 install needs v0.14.0,
v0.15.0, then v0.16.0; a v0.14.0 install needs v0.15.0,
v0.16.0, then v0.17.0; a v0.15.0 install needs v0.16.0 then v0.17.0; a
v0.16.0 install needs only v0.17.0.

Two gaps in the script names are deliberate, not missing steps: there is no
v0.2→v0.3 script because v0.2/v0.3 detection is lumped — the v0.3→v0.4 step
handles both layouts (verified benign). There is no v0.9.4→v0.9.6 script
because v0.9.5 and v0.9.6 were plugin-side releases only — nothing in a target
install changed.

Note: `migrate-v0.9.2-to-v0.9.3.sh` requires the installed `espalier-review`
SKILL to carry a `## Production-Readiness Checks` section. Fresh v0.9.0+ inits
have it from the template, and `migrate-v0.8.2-to-v0.9.0.sh` now appends it to
migrated installs. An install migrated by an older build of that script lacks the
section — re-running the v0.9.0 step (idempotent) adds it, which is why the chain
below never skips ahead.

### Step 0: Migration barrier (ENFORCED pre-flight — before any detection or apply)

Migrations rewrite installed skills and hooks; running one over uncommitted
work or a half-finished pipeline change destroys context. Three checks, all
enforced — not recommendations:

```bash
# 1. Clean working tree — abort otherwise (nothing may be applied over
#    uncommitted changes; migrations must be their own commit).
if [ -n "$(git status --porcelain)" ]; then
  echo "BARRIER: working tree not clean — commit or stash first, then re-run /espalier-migrate."
fi

# 2. No in-flight pipeline change. A change is in-flight unless its
#    `- Status:` matches the terminal-status vocabulary pre-push-gate.sh uses
#    (COMPLETE|ABORTED|ABORTED_LATE|ESCALATED|ESCALATED_LATE|FILED). A state
#    file with a MISSING or unrecognized status counts as ACTIVE — fail
#    closed, exactly like the push gate.
ACTIVE=""
for f in espalier/changes/*/*/pipeline-state.md; do
  [ -f "$f" ] || continue
  grep -qE '^- Status:[[:space:]]*(COMPLETE|ABORTED|ABORTED_LATE|ESCALATED|ESCALATED_LATE|FILED)\b' "$f" \
    || ACTIVE="$ACTIVE $f"
done
[ -n "$ACTIVE" ] && echo "BARRIER: in-flight change(s):$ACTIVE — finish or abandon first."

# 3. Current branch must equal the canonical branch. Read the key when the
#    install has it (v0.16.0+); older installs fall back to the remote HEAD
#    detection, then `main`.
B=$(grep '^canonical-branch:' espalier/.espalier-config 2>/dev/null | awk '{print $2}')
if [ -z "$B" ]; then
  R=origin; git remote 2>/dev/null | grep -qx upstream && R=upstream
  REF=$(git symbolic-ref --short "refs/remotes/$R/HEAD" 2>/dev/null)
  B=${REF#"$R"/}; [ -n "$B" ] || B=main
fi
CUR=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
[ "$CUR" = "$B" ] || echo "BARRIER: on branch '$CUR', canonical is '$B'."
```

Any `BARRIER:` line on stdout means STOP:

- Checks 1-2 are hard aborts — surface the line and end the migration run.
- Check 3 may be acknowledged: ask the user via `AskUserQuestion`
  ("Migrate on branch '{CUR}' instead of the canonical '{B}'? A migration on
  a feature branch strands the upgrade until that branch merges and every
  other branch keeps the old install."). Proceed ONLY on an explicit
  "migrate here anyway" acknowledgment; on an unattended run there is no one
  to acknowledge — abort.

### Step 1: Preflight + detect install version

Run from the current working directory (must be the target project root):

```bash
NEEDS_V01_V02=no
NEEDS_V03_V04=no
NEEDS_V04_V05=no
NEEDS_V05_PATCH=no
NEEDS_V05_V06=no
NEEDS_V06_V07=no
NEEDS_V07_V08=no
NEEDS_V08_PATCH=no
NEEDS_V082_PATCH=no
NEEDS_V09_MINOR=no
NEEDS_V091_PATCH=no
NEEDS_V092_PATCH=no
NEEDS_V093_PATCH=no
NEEDS_V094_PATCH=no
NEEDS_V0100_PATCH=no
NEEDS_V0110_PATCH=no
NEEDS_V0120_PATCH=no
NEEDS_V0130_PATCH=no
NEEDS_V0131_PATCH=no
NEEDS_V0132_PATCH=no
NEEDS_V0140_PATCH=no
NEEDS_V0150_PATCH=no
NEEDS_V0160_PATCH=no
NEEDS_V0170_PATCH=no

if [ ! -d "harness" ] && [ ! -d "espalier" ]; then
  echo "ERROR: no harness/ or espalier/ dir found — not a target install."
  echo "Use /espalier-init to set up Espalier in a fresh project."
  exit 1
fi

if [ -d "harness" ]; then
  # Pre-rename install. v0.1.x has no .merge-hook-decision; v0.2/v0.3.x has one.
  if [ ! -f "harness/.merge-hook-decision" ]; then
    NEEDS_V01_V02=yes
  fi
  NEEDS_V03_V04=yes          # harness/ always needs the rename
  NEEDS_V04_V05=yes          # ...then the doc-drift upgrade
  NEEDS_V05_PATCH=yes        # ...then the v0.5.3 coder-agent patch
  NEEDS_V05_V06=yes          # ...then the v0.6 Stage 1 grill
  NEEDS_V06_V07=yes          # ...then the v0.7 ask lane
  NEEDS_V07_V08=yes          # ...then the v0.8 approval gate
  NEEDS_V08_PATCH=yes        # ...then the v0.8.1 impact-analysis agent patch
  NEEDS_V082_PATCH=yes       # ...then the v0.8.2 re-review fixpoint loop
  NEEDS_V09_MINOR=yes        # ...then the v0.9.0 security audit
  NEEDS_V091_PATCH=yes       # ...then the v0.9.1 configurable escalation caps
  NEEDS_V092_PATCH=yes       # ...then the v0.9.2 correctness patch
  NEEDS_V093_PATCH=yes       # ...then the v0.9.3 skill-clarity patch
  NEEDS_V094_PATCH=yes       # ...then the v0.9.4 security-skill patch
  NEEDS_V0100_PATCH=yes      # ...then the v0.10.0 push-gate reshape
  NEEDS_V0110_PATCH=yes      # ...then the v0.11.0 hook exit-code release
  NEEDS_V0120_PATCH=yes      # ...then the v0.12.0 grill blind-spot pass
  NEEDS_V0130_PATCH=yes      # ...then the v0.13.0 minimalism release
  NEEDS_V0131_PATCH=yes      # ...then the v0.13.1 minimalism polish patch
  NEEDS_V0132_PATCH=yes      # ...then the v0.13.2 readability release
  NEEDS_V0140_PATCH=yes      # ...then the v0.14.0 codex platform release
  NEEDS_V0150_PATCH=yes      # ...then the v0.15.0 copilot platform release
  NEEDS_V0160_PATCH=yes      # ...then the v0.16.0 multi-dev maintenance floor
  NEEDS_V0170_PATCH=yes      # ...then the v0.17.0 gardener/per-key release
elif [ -d "espalier" ]; then
  # Already renamed. v0.4.x still needs the doc-drift upgrade.
  if [ ! -f "espalier/hooks/drift-detect.sh" ] || [ ! -f "espalier/.doctor-cadence" ]; then
    NEEDS_V04_V05=yes        # v0.4.x → doc-drift upgrade
  fi
  # v0.5.3: harness-coder.md gains an "## Editing Discipline" section. It is a
  # per-project file, so a plugin update never reaches an existing install.
  if ! grep -qF "## Editing Discipline" espalier/agents/harness-coder.md 2>/dev/null; then
    NEEDS_V05_PATCH=yes
  fi
  # v0.6.0: the espalier-grill skill is new AND must be wired into Stage 1 of
  # espalier-requirements. Absence of either signals a pre-v0.6 install.
  if [ ! -f "espalier/skills/espalier-grill/SKILL.md" ] \
     || ! grep -q "Grill the requirement" espalier/skills/espalier-requirements/SKILL.md 2>/dev/null; then
    NEEDS_V05_V06=yes
  fi
  # v0.7.0: the espalier-ask skill is new. Its absence signals a pre-v0.7
  # install (independent of grill — migrations run in order, so v0.6 installs
  # grill before v0.7 installs ask).
  if [ ! -f "espalier/skills/espalier-ask/SKILL.md" ]; then
    NEEDS_V06_V07=yes
  fi
  # v0.8.0: both pipelines gain a requirements approval gate. It is wired into
  # the pure-copy espalier skill; absence of the gate text signals pre-v0.8.
  if ! grep -q "Requirements Approval Gate" espalier/skills/espalier/SKILL.md 2>/dev/null; then
    NEEDS_V07_V08=yes
  fi
  # v0.8.1: the two sub-agents gain change-impact / runtime-surface guidance.
  # Per-project files, so a plugin update never reaches an existing install.
  # Either section missing signals a pre-v0.8.1 install.
  if ! grep -qF "## Change Impact Analysis" espalier/agents/harness-coder.md 2>/dev/null \
     || ! grep -qF "## Runtime-Surface Review" espalier/agents/harness-reviewer.md 2>/dev/null; then
    NEEDS_V08_PATCH=yes
  fi
  # v0.8.2: code review becomes a fixpoint loop + push-gate certificate. The loop
  # rides the pure-copy pipeline files; the reviewer gains a Re-review Rounds
  # section and the push gate gains a Reviewed-Diff certificate (both per-project
  # files a plugin update cannot reach). Any of the three missing ⇒ pre-v0.8.2.
  if ! grep -qF "fixpoint loop" espalier/pipeline.md 2>/dev/null \
     || ! grep -qF "## Re-review Rounds" espalier/agents/harness-reviewer.md 2>/dev/null \
     || ! grep -qF "Reviewed-Diff:" espalier/hooks/pre-push-gate.sh 2>/dev/null; then
    NEEDS_V082_PATCH=yes
  fi
  # v0.9.0: the security audit. A new harness-security agent joins Stage 4 as a
  # review panel; a security-standards rule + espalier-security skill are added and
  # the coder/reviewer/gate gain security sections. v0.9.0 also ships the
  # /espalier-audit repo-wide lane (espalier-audit skill + a Repo-Audit Mode
  # section in the security agent). The "review panel" text rides the pure-copy
  # pipeline; harness-security.md is a new per-project file a plugin update
  # cannot reach — any absent ⇒ pre-v0.9.0 (or a pre-fold v0.9.0 the script
  # completes idempotently).
  #
  # The espalier-review SKILL's "## Production-Readiness Checks" is in this set on
  # purpose. An install migrated by an older build of migrate-v0.8.2-to-v0.9.0.sh
  # never received it (that script declared the path but never wrote to it), and
  # migrate-v0.9.2-to-v0.9.3.sh dies without it. Flagging it here re-runs the
  # (idempotent) v0.9.0 step, which appends the section before v0.9.3 needs it.
  if ! grep -qF "review panel" espalier/pipeline.md 2>/dev/null \
     || [ ! -f espalier/agents/harness-security.md ] \
     || [ ! -f espalier/skills/espalier-audit/SKILL.md ] \
     || ! grep -qF "## Repo-Audit Mode" espalier/agents/harness-security.md 2>/dev/null \
     || [ ! -f espalier/rules/production-standards.md ] \
     || ! grep -qF "## Production-Aware Coding" espalier/agents/harness-coder.md 2>/dev/null \
     || ! grep -qF "## Production-Readiness Checks" espalier/skills/espalier-review/SKILL.md 2>/dev/null \
     || ! grep -qF "cd defensively too" espalier/hooks/pre-push-gate.sh 2>/dev/null; then
    NEEDS_V09_MINOR=yes
  fi
  # v0.9.1: the review-round + rollback caps become configurable via a tracked
  # espalier/.espalier-config, and the pure-copy pipeline prose is refreshed to
  # read it. A missing config file OR a pipeline.md that still hardcodes the limit
  # (no "max-code-rounds" reference) ⇒ pre-v0.9.1.
  if [ ! -f espalier/.espalier-config ] \
     || ! grep -qF "max-code-rounds" espalier/pipeline.md 2>/dev/null; then
    NEEDS_V091_PATCH=yes
  fi
  # v0.9.2: correctness patch. Pre-v0.9.2 signals: the fix lane still calls
  # the never-shipped _fire_late_escalation_prompt helper (pure-copy file), OR
  # the per-project push gate still selects by mtime alone (no active-change
  # text), OR the shipped scout-prompts lacks scout 1.11. Any ⇒ needed.
  if grep -qF "_fire_late_escalation_prompt" espalier/skills/espalier-fix/SKILL.md 2>/dev/null \
     || ! grep -qF "Find the ACTIVE change" espalier/hooks/pre-push-gate.sh 2>/dev/null \
     || ! grep -qF "Scout 1.11" espalier/.scout-prompts.md 2>/dev/null; then
    NEEDS_V092_PATCH=yes
  fi
  # v0.9.3: skill-clarity patch. Same two markers migrate-v0.9.2-to-v0.9.3.sh uses
  # for its own idempotency check — keep them in sync with that script:
  #   grill  → "Coverage guard (before returning"
  #   review → "SINGLE SOURCE for these checks"
  # Either missing ⇒ pre-v0.9.3 (or a half-applied run the script finishes).
  if ! grep -qF "Coverage guard (before returning" espalier/skills/espalier-grill/SKILL.md 2>/dev/null \
     || ! grep -qF "SINGLE SOURCE for these checks" espalier/skills/espalier-review/SKILL.md 2>/dev/null; then
    NEEDS_V093_PATCH=yes
  fi
  # v0.9.4: security-skill patch. Same two markers migrate-v0.9.3-to-v0.9.4.sh uses
  # for its own idempotency check — keep them in sync with that script:
  #   harness-security AGENT   → "self-noops on changes with no sensitive surface"
  #   espalier-security SKILL  → "abuse-test recipe for"
  # Both are per-project files a plugin update cannot reach. Either missing ⇒
  # pre-v0.9.4. Guarded on the files existing: a pre-v0.9.0 install has neither,
  # and the v0.9.0 step creates them before this step runs.
  if [ -f espalier/agents/harness-security.md ] && [ -f espalier/skills/espalier-security/SKILL.md ]; then
    if ! grep -qF "self-noops on changes with no sensitive surface" espalier/agents/harness-security.md 2>/dev/null \
       || ! grep -qF "abuse-test recipe for" espalier/skills/espalier-security/SKILL.md 2>/dev/null; then
      NEEDS_V094_PATCH=yes
    fi
  else
    NEEDS_V094_PATCH=yes   # v0.9.0 will create them; v0.9.4 then sharpens them
  fi
  # v0.10.0: the gate's three check steps become run_build/run_lint/run_tests, so a
  # {..._command} may be a multi-line block, and build/lint stop discarding stderr.
  # ALL THREE functions must be present — running the v0.9.2 step against a v0.10.0
  # plugin re-splices only the test span, leaving run_tests with old build/lint.
  # A gate customised past the template shape is detected here too; the script
  # recognises it and exits 0 without touching it.
  # A `v0.10.0-gate:` marker in espalier/.migrations-skipped means the script
  # already declined this customised gate once — treat the version as handled
  # (manual): report it, do not re-propose the patch every run.
  if grep -qF 'v0.10.0-gate:' espalier/.migrations-skipped 2>/dev/null; then
    NEEDS_V0100_PATCH=no
  elif [ -f espalier/hooks/pre-push-gate.sh ] && { \
       ! grep -qF 'run_build() {' espalier/hooks/pre-push-gate.sh 2>/dev/null \
       || ! grep -qF 'run_lint() {' espalier/hooks/pre-push-gate.sh 2>/dev/null \
       || ! grep -qF 'run_tests() {' espalier/hooks/pre-push-gate.sh 2>/dev/null; }; then
    NEEDS_V0100_PATCH=yes
  fi
  # v0.11.0: hooks must block with exit code 2 (exit 1 is a silent no-op in
  # Claude Code) and the Stage 4/6 gates must read the verdict WORD. The gate
  # marker is the v0.11 header comment — NOT a bare `exit 2` grep: a gate
  # chain-migrated by the v0.9.2/v0.10.0 span splices already carries exit-2
  # spans while its stage/cert/secret sections still exit 1. Same E5 rule: a
  # `v0.11.0-gate:` marker means the customised gate was handled manually —
  # the script itself skips the gate step on it, so re-running here only
  # refreshes the skill/agent side.
  if ! grep -qF 'Exit-code contract (Claude Code PreToolUse semantics)' espalier/hooks/pre-push-gate.sh 2>/dev/null \
     || ! grep -qF 'Advance ONLY when EVERY record' espalier/skills/espalier/SKILL.md 2>/dev/null; then
    NEEDS_V0110_PATCH=yes
  fi
  if grep -qF 'v0.11.0-gate:' espalier/.migrations-skipped 2>/dev/null \
     && grep -qF 'Advance ONLY when EVERY record' espalier/skills/espalier/SKILL.md 2>/dev/null; then
    NEEDS_V0110_PATCH=no   # handled (manual) — reported once, not re-proposed
  fi
  # v0.12.0: the grill skill gains Step 1.5 (the rules/wiki blind-spot pass). It
  # is a pure-copy pipeline file, so a plugin update never reaches an existing
  # install — absence of Step 1.5 in the installed grill skill signals pre-v0.12.
  if ! grep -qF 'Step 1.5 — Blind-spot pass' espalier/skills/espalier-grill/SKILL.md 2>/dev/null; then
    NEEDS_V0120_PATCH=yes
  fi
  # v0.13.0: the coder gains the Solution Selection Ladder and the reviewer the
  # advisory Minimalism Review. All four touched files are per-project files a
  # plugin update cannot reach — any of the four markers missing ⇒ pre-v0.13.
  # Keep these in sync with migrate-v0.12.0-to-v0.13.0.sh's own idempotency check.
  if ! grep -qF '## Solution Selection Ladder' espalier/agents/harness-coder.md 2>/dev/null \
     || ! grep -qF '## Minimalism Review' espalier/agents/harness-reviewer.md 2>/dev/null \
     || ! grep -qF -- '## Solution Selection (keep it lean)' espalier/skills/espalier-coding/SKILL.md 2>/dev/null \
     || ! grep -qF -- 'Gate (pass condition)' espalier/skills/espalier-review/SKILL.md 2>/dev/null; then
    NEEDS_V0130_PATCH=yes
  fi
  # v0.13.1: post-release polish on v0.13.0. The coding skill gains the
  # By-Stage section, the reviewer's Review Process gains the Stage 6
  # abuse-test step (findings renumber to 8), and the review skill's
  # code-review loop gains its Gate line. All three are per-project files a
  # plugin update cannot reach — any marker missing ⇒ pre-v0.13.1. Keep these
  # in sync with migrate-v0.13.0-to-v0.13.1.sh's own idempotency check.
  if ! grep -qF -- '## How This Skill Applies by Stage' espalier/skills/espalier-coding/SKILL.md 2>/dev/null \
     || ! grep -qF -- 'run the **Security Abuse-Test Coverage**' espalier/agents/harness-reviewer.md 2>/dev/null \
     || ! grep -qF -- 'max-code-rounds' espalier/skills/espalier-review/SKILL.md 2>/dev/null; then
    NEEDS_V0131_PATCH=yes
  fi
  # v0.13.2: the readability release. The coder ladder tie-break becomes
  # clarity-then-brevity, coding-standards gains the naming-intent floor +
  # Comments & Docstrings, and the reviewer gains the advisory Readability
  # Review (ONE P1: a cryptic EXPORTED/public name). All touched files are
  # per-project files a plugin update cannot reach — any marker missing ⇒
  # pre-v0.13.2. Keep these in sync with migrate-v0.13.1-to-v0.13.2.sh's own
  # idempotency check.
  if ! grep -qF -- 'clarity then brevity break ties' espalier/agents/harness-coder.md 2>/dev/null \
     || ! grep -qF -- '## Readability Review' espalier/agents/harness-reviewer.md 2>/dev/null \
     || ! grep -qF -- '## Comments & Docstrings' espalier/rules/coding-standards.md 2>/dev/null \
     || ! grep -qF -- 'clarity then brevity break ties' espalier/skills/espalier-coding/SKILL.md 2>/dev/null \
     || ! grep -qF -- 'Readability: names state intent' espalier/skills/espalier-review/SKILL.md 2>/dev/null; then
    NEEDS_V0132_PATCH=yes
  fi
  # v0.14.0: the codex platform release. The two plugin-owned hook wrappers
  # become platform-neutral (Codex apply_patch parsing; argv-array join). Any
  # marker missing ⇒ pre-v0.14.0. Keep in sync with
  # migrate-v0.13.2-to-v0.14.0.sh's own idempotency check. (Codex WIRING is
  # opt-in and never a detection signal — a claude-only install is complete.)
  if ! grep -qF -- 'apply_patch' espalier/hooks/post-edit-wrapper.sh 2>/dev/null \
     || ! grep -qF -- 'isinstance(c, list)' espalier/hooks/pre-push-gate-wrapper.sh 2>/dev/null; then
    NEEDS_V0140_PATCH=yes
  fi
  # v0.15.0: the copilot platform release. The always-delta is one NEW
  # plugin-owned file — the camelCase hook shim. Keep in sync with
  # migrate-v0.14.0-to-v0.15.0.sh's own idempotency check. (Copilot WIRING is
  # opt-in and never a detection signal.)
  if [ ! -f espalier/hooks/copilot-hook-adapter.sh ]; then
    NEEDS_V0150_PATCH=yes
  fi
  # v0.16.0: the multi-dev maintenance floor. Detection mirrors the script's
  # own all-marker check (a --force bootstrap from a newer plugin can
  # pre-install the config/attribute artifacts, so a subset detector would
  # skip the still-missing surgical rule edit — keep in sync with
  # migrate-v0.15.0-to-v0.16.0.sh). Any marker missing ⇒ pre-v0.16.0.
  if ! grep -qxF 'espalier/.ask-gaps.tsv merge=union' .gitattributes 2>/dev/null \
     || ! grep -qE '^canonical-remote: .+' espalier/.espalier-config 2>/dev/null \
     || ! grep -qE '^canonical-branch: .+' espalier/.espalier-config 2>/dev/null \
     || ! grep -qF 'ESPALIER MAINTENANCE COMMITS v1' espalier/rules/development-process.md 2>/dev/null \
     || ! grep -qF 'Multi-Developer Maintenance' espalier/pipeline.md 2>/dev/null \
     || ! grep -qF 'Multi-Developer Discipline' espalier/skills/espalier-prune/SKILL.md 2>/dev/null \
     || ! grep -qF 'Multi-Developer Discipline' espalier/skills/espalier-doctor/SKILL.md 2>/dev/null \
     || ! grep -qF 'conv_fold' espalier/skills/espalier/SKILL.md 2>/dev/null \
     || ! grep -qF 'conv_fold' espalier/skills/espalier-fix/SKILL.md 2>/dev/null \
     || ! grep -qF 'conv_fold' espalier/hooks/drift-helpers.sh 2>/dev/null; then
    NEEDS_V0160_PATCH=yes
  fi
  # v0.17.0: the B-team release rides pure-copy files only. Keep these
  # markers in sync with migrate-v0.16.0-to-v0.17.0.sh's own idempotency
  # check. Any missing ⇒ pre-v0.17.0.
  if ! grep -qF 'doctor_stamp_shared' espalier/hooks/drift-helpers.sh 2>/dev/null \
     || ! grep -qF 'doctor_stamp_shared' espalier/skills/espalier-doctor/SKILL.md 2>/dev/null \
     || ! grep -qiF 'gardener' espalier/skills/espalier-prune/SKILL.md 2>/dev/null \
     || ! grep -qiF 'gardener rota' espalier/skills/espalier/SKILL.md 2>/dev/null \
     || ! grep -qiF 'gardener rota' espalier/skills/espalier-fix/SKILL.md 2>/dev/null \
     || ! grep -qiF 'keep both lines' espalier/pipeline.md 2>/dev/null; then
    NEEDS_V0170_PATCH=yes
  fi
fi

if [ "$NEEDS_V01_V02" = no ] && [ "$NEEDS_V03_V04" = no ] \
   && [ "$NEEDS_V04_V05" = no ] && [ "$NEEDS_V05_PATCH" = no ] \
   && [ "$NEEDS_V05_V06" = no ] && [ "$NEEDS_V06_V07" = no ] \
   && [ "$NEEDS_V07_V08" = no ] && [ "$NEEDS_V08_PATCH" = no ] \
   && [ "$NEEDS_V082_PATCH" = no ] && [ "$NEEDS_V09_MINOR" = no ] \
   && [ "$NEEDS_V091_PATCH" = no ] && [ "$NEEDS_V092_PATCH" = no ] \
   && [ "$NEEDS_V093_PATCH" = no ] && [ "$NEEDS_V094_PATCH" = no ] \
   && [ "$NEEDS_V0100_PATCH" = no ] && [ "$NEEDS_V0110_PATCH" = no ] \
   && [ "$NEEDS_V0120_PATCH" = no ] && [ "$NEEDS_V0130_PATCH" = no ] \
   && [ "$NEEDS_V0131_PATCH" = no ] && [ "$NEEDS_V0132_PATCH" = no ] \
   && [ "$NEEDS_V0140_PATCH" = no ] && [ "$NEEDS_V0150_PATCH" = no ] \
   && [ "$NEEDS_V0160_PATCH" = no ] && [ "$NEEDS_V0170_PATCH" = no ]; then
  echo "Already fully up to date. Nothing to do."
  exit 0
fi
```

Report the detected plan to the user (which migration(s) will run).

### Step 2: Locate migration scripts

The skill resolves its own plugin root — no path guessing. `${CLAUDE_SKILL_DIR}`
is set by Claude Code to the directory of the running skill
(`<plugin>/skills/espalier-migrate`); the plugin root, where `scripts/` lives,
is two levels up. This resolves the *installed* plugin in every layout —
marketplace cache (`~/.claude/plugins/cache/...`), dev checkout, or symlink —
never a stray `$HOME` checkout that merely shares the name.

```bash
PLUGIN_DIR=""
# Primary: derive the plugin root from the skill's own location.
if [ -n "${CLAUDE_SKILL_DIR:-}" ] \
   && [ -f "${CLAUDE_SKILL_DIR}/../../scripts/migrate-v0.16.0-to-v0.17.0.sh" ]; then
  PLUGIN_DIR="$(cd "${CLAUDE_SKILL_DIR}/../.." && pwd)"
fi

# Fallback (rare — e.g. CLAUDE_SKILL_DIR unset): explicit override, then a
# known dev-checkout location.
if [ -z "$PLUGIN_DIR" ]; then
  for candidate in "${ESPALIER_PLUGIN_DIR:-}" "$HOME/repos/espalier-engineering"; do
    [ -n "$candidate" ] || continue
    if [ -f "$candidate/scripts/migrate-v0.16.0-to-v0.17.0.sh" ]; then
      PLUGIN_DIR="$candidate"
      break
    fi
  done
fi

if [ -z "$PLUGIN_DIR" ]; then
  echo "ERROR: couldn't locate the Espalier plugin." >&2
  echo "If it is installed, update it: /plugin update espalier-engineering" >&2
  echo "Or set ESPALIER_PLUGIN_DIR to your espalier-engineering checkout." >&2
  exit 1
fi
```

The probe is the NEWEST migration script, so a plugin that predates the current
chain fails to resolve rather than resolving and then dying on a missing script
mid-apply. If the primary path misses and the fallback fires, the plugin install
is likely stale (no `migrate-v0.16.0-to-v0.17.0.sh`) — tell the user to
`/plugin update espalier-engineering` first. Bump this probe whenever a new
migration script is added.

### Step 3: Show dry-run preview for each applicable migration

Run the dry-run for each needed migration, in order, and surface the output
verbatim:

```bash
[ "$NEEDS_V01_V02" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.1-to-v0.2.sh" --dry-run --plugin-dir="$PLUGIN_DIR/skills/espalier-init"
[ "$NEEDS_V03_V04" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.3-to-v0.4.sh" --dry-run
[ "$NEEDS_V04_V05" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.4-to-v0.5.sh" --dry-run --plugin-dir="$PLUGIN_DIR"
[ "$NEEDS_V05_PATCH" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.5.2-to-v0.5.3.sh" --dry-run
[ "$NEEDS_V05_V06" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.5-to-v0.6.sh" --dry-run --plugin-dir="$PLUGIN_DIR"
[ "$NEEDS_V06_V07" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.6-to-v0.7.sh" --dry-run --plugin-dir="$PLUGIN_DIR"
[ "$NEEDS_V07_V08" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.7-to-v0.8.sh" --dry-run --plugin-dir="$PLUGIN_DIR"
[ "$NEEDS_V08_PATCH" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.8-to-v0.8.1.sh" --dry-run
[ "$NEEDS_V082_PATCH" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.8.1-to-v0.8.2.sh" --dry-run --plugin-dir="$PLUGIN_DIR"
[ "$NEEDS_V09_MINOR" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.8.2-to-v0.9.0.sh" --dry-run --plugin-dir="$PLUGIN_DIR"
[ "$NEEDS_V091_PATCH" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.9.0-to-v0.9.1.sh" --dry-run --plugin-dir="$PLUGIN_DIR"
[ "$NEEDS_V092_PATCH" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.9.1-to-v0.9.2.sh" --dry-run --plugin-dir="$PLUGIN_DIR"
[ "$NEEDS_V093_PATCH" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.9.2-to-v0.9.3.sh" --dry-run --plugin-dir="$PLUGIN_DIR"
[ "$NEEDS_V094_PATCH" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.9.3-to-v0.9.4.sh" --dry-run --plugin-dir="$PLUGIN_DIR"
[ "$NEEDS_V0100_PATCH" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.9.6-to-v0.10.0.sh" --dry-run --plugin-dir="$PLUGIN_DIR"
[ "$NEEDS_V0110_PATCH" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.10.0-to-v0.11.0.sh" --dry-run --plugin-dir="$PLUGIN_DIR"
[ "$NEEDS_V0120_PATCH" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.11.0-to-v0.12.0.sh" --dry-run --plugin-dir="$PLUGIN_DIR"
[ "$NEEDS_V0130_PATCH" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.12.0-to-v0.13.0.sh" --dry-run --plugin-dir="$PLUGIN_DIR"
[ "$NEEDS_V0131_PATCH" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.13.0-to-v0.13.1.sh" --dry-run --plugin-dir="$PLUGIN_DIR"
[ "$NEEDS_V0132_PATCH" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.13.1-to-v0.13.2.sh" --dry-run --plugin-dir="$PLUGIN_DIR"
[ "$NEEDS_V0140_PATCH" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.13.2-to-v0.14.0.sh" --dry-run --plugin-dir="$PLUGIN_DIR" $WITH_CODEX_FLAG
[ "$NEEDS_V0150_PATCH" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.14.0-to-v0.15.0.sh" --dry-run --plugin-dir="$PLUGIN_DIR" $WITH_COPILOT_FLAG
[ "$NEEDS_V0160_PATCH" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.15.0-to-v0.16.0.sh" --dry-run --plugin-dir="$PLUGIN_DIR" $CODEOWNERS_FLAGS
[ "$NEEDS_V0170_PATCH" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.16.0-to-v0.17.0.sh" --dry-run --plugin-dir="$PLUGIN_DIR"
```

A dry-run for a step whose prerequisite has not been applied yet may refuse with
an error (e.g. the v0.9.2 preview needs a `pipeline.md` that the v0.9.1 step
rewrites). That is expected in a multi-step chain — the refusal is the script
guarding its own precondition, not a failure. Surface it and continue; Step 6
applies the steps in order, so the prerequisite is satisfied by then.

### Step 4: If v0.4→v0.5 applies, pick the doctor cadence

The v0.4→v0.5 upgrade installs `/espalier-doctor`, a periodic drift scan. Ask
the user how often it should run (`AskUserQuestion`):

```
How often should /espalier-doctor re-scout the codebase for artifact drift?
A scan is activity-gated — an idle repo never triggers one.

  1. Every change   → every-change
  2. Weekly         → weekly   (recommended)
  3. Monthly        → monthly
  4. On-demand only → manual
```

Cache the answer as `$DOCTOR_CADENCE` (default `weekly`). It is editable later
in `espalier/.doctor-cadence`.

### Step 4b: If v0.14.0 applies, ask about Codex wiring

The wrapper refresh always runs; the Codex WIRING is opt-in. Skip the question
entirely if `grep -q codex espalier/.platforms` already succeeds (wired — set
`WITH_CODEX_FLAG=""`). Otherwise ask (`AskUserQuestion`):

```
v0.14.0 can additionally wire this repo for Codex (OpenAI's coding agent):
.agents/skills/ symlinks, an AGENTS.md Espalier section, .codex/config.toml
quality-gate hooks, and .codex/agents/ sub-agents. Claude wiring is untouched.

  1. Yes — teammates (or I) use Codex here   → WITH_CODEX_FLAG=--with-codex
  2. No — Claude Code only (default)          → WITH_CODEX_FLAG=""
```

Cache the literal flag string as `$WITH_CODEX_FLAG` and substitute it into the
Step 3 dry-run and Step 6 apply commands (it expands to nothing when empty).
Wiring later is one command: `bash <plugin>/scripts/migrate-v0.13.2-to-v0.14.0.sh --with-codex --yes`.

### Step 4c: If v0.15.0 applies, ask about Copilot wiring

The adapter install always runs; the Copilot WIRING is opt-in. Skip the
question entirely if `grep -q copilot espalier/.platforms` already succeeds
(wired — set `WITH_COPILOT_FLAG=""`). Otherwise ask (`AskUserQuestion`):

```
v0.15.0 can additionally wire this repo for GitHub Copilot: .github/skills/
symlinks (Agent Skills for VS Code / CLI / cloud agent), a
.github/copilot-instructions.md Espalier section, @harness-* custom agents,
and .github/hooks quality gates. Claude/Codex wiring is untouched.

  1. Yes — teammates (or I) use Copilot here   → WITH_COPILOT_FLAG=--with-copilot
  2. No — not needed (default)                  → WITH_COPILOT_FLAG=""
```

Cache the literal flag string as `$WITH_COPILOT_FLAG` and substitute it into
the Step 3 dry-run and Step 6 apply commands (it expands to nothing when
empty). Wiring later is one command:
`bash <plugin>/scripts/migrate-v0.14.0-to-v0.15.0.sh --with-copilot --yes`.

### Step 4d: If v0.16.0 applies, ask about CODEOWNERS ownership routing

The maintenance-floor refresh always runs; the CODEOWNERS block is opt-in.
The SCRIPT never prompts (the runner invokes every script `--yes`) — collect
the handles HERE, before apply. Skip the question entirely when a
`>>> ESPALIER OWNERS v1 >>>` marker already exists in `.github/CODEOWNERS`,
`CODEOWNERS`, or `docs/CODEOWNERS` (set `CODEOWNERS_FLAGS=""`), and on an
unattended run (skipped — wiring later is one
`bootstrap --wire-only --codeowners-rules=… --codeowners-wiki=…` run).
Otherwise ask (`AskUserQuestion`):

```
v0.16.0 can route espalier rule/wiki changes to owners for review via a
CODEOWNERS block (advisory until "Require review from Code Owners" branch
protection is on). Add it?

  1. Skip (default)                    → CODEOWNERS_FLAGS=""
  2. Yes — provide handles via Other   → e.g. "@platform-team @docs-team"
       (first = espalier/rules/ owner, second = espalier/wiki/ owner; either
       may be omitted) → CODEOWNERS_FLAGS="--codeowners-rules=<h1> --codeowners-wiki=<h2>"
       (drop the flag for an omitted handle)
```

Cache the literal flag string as `$CODEOWNERS_FLAGS` and substitute it into
the Step 3 dry-run and Step 6 apply commands (it expands to nothing when
empty).

### Step 5: Confirm with the user

Use `AskUserQuestion`:

```
The dry-run preview above shows what will change. Proceed?

Options:
  1. Apply all needed migrations, in order
  2. Apply only the next one (stop after that)
  3. Cancel — don't apply anything
```

### Step 6: Apply migration(s) in order

Apply each needed migration IN ORDER. Never reorder — each assumes the prior
completed.

```bash
[ "$NEEDS_V01_V02" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.1-to-v0.2.sh" --yes --plugin-dir="$PLUGIN_DIR/skills/espalier-init"
[ "$NEEDS_V03_V04" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.3-to-v0.4.sh" --yes
[ "$NEEDS_V04_V05" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.4-to-v0.5.sh" --yes --plugin-dir="$PLUGIN_DIR" --doctor-cadence="$DOCTOR_CADENCE"
[ "$NEEDS_V05_PATCH" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.5.2-to-v0.5.3.sh" --yes
[ "$NEEDS_V05_V06" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.5-to-v0.6.sh" --yes --plugin-dir="$PLUGIN_DIR"
[ "$NEEDS_V06_V07" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.6-to-v0.7.sh" --yes --plugin-dir="$PLUGIN_DIR"
[ "$NEEDS_V07_V08" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.7-to-v0.8.sh" --yes --plugin-dir="$PLUGIN_DIR"
[ "$NEEDS_V08_PATCH" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.8-to-v0.8.1.sh" --yes
[ "$NEEDS_V082_PATCH" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.8.1-to-v0.8.2.sh" --yes --plugin-dir="$PLUGIN_DIR"
[ "$NEEDS_V09_MINOR" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.8.2-to-v0.9.0.sh" --yes --plugin-dir="$PLUGIN_DIR"
[ "$NEEDS_V091_PATCH" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.9.0-to-v0.9.1.sh" --yes --plugin-dir="$PLUGIN_DIR"
[ "$NEEDS_V092_PATCH" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.9.1-to-v0.9.2.sh" --yes --plugin-dir="$PLUGIN_DIR"
[ "$NEEDS_V093_PATCH" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.9.2-to-v0.9.3.sh" --yes --plugin-dir="$PLUGIN_DIR"
[ "$NEEDS_V094_PATCH" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.9.3-to-v0.9.4.sh" --yes --plugin-dir="$PLUGIN_DIR"
[ "$NEEDS_V0100_PATCH" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.9.6-to-v0.10.0.sh" --yes --plugin-dir="$PLUGIN_DIR"
[ "$NEEDS_V0110_PATCH" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.10.0-to-v0.11.0.sh" --yes --plugin-dir="$PLUGIN_DIR"
[ "$NEEDS_V0120_PATCH" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.11.0-to-v0.12.0.sh" --yes --plugin-dir="$PLUGIN_DIR"
[ "$NEEDS_V0130_PATCH" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.12.0-to-v0.13.0.sh" --yes --plugin-dir="$PLUGIN_DIR"
[ "$NEEDS_V0131_PATCH" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.13.0-to-v0.13.1.sh" --yes --plugin-dir="$PLUGIN_DIR"
[ "$NEEDS_V0132_PATCH" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.13.1-to-v0.13.2.sh" --yes --plugin-dir="$PLUGIN_DIR"
[ "$NEEDS_V0140_PATCH" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.13.2-to-v0.14.0.sh" --yes --plugin-dir="$PLUGIN_DIR" $WITH_CODEX_FLAG
[ "$NEEDS_V0150_PATCH" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.14.0-to-v0.15.0.sh" --yes --plugin-dir="$PLUGIN_DIR" $WITH_COPILOT_FLAG
[ "$NEEDS_V0160_PATCH" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.15.0-to-v0.16.0.sh" --yes --plugin-dir="$PLUGIN_DIR" $CODEOWNERS_FLAGS
[ "$NEEDS_V0170_PATCH" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.16.0-to-v0.17.0.sh" --yes --plugin-dir="$PLUGIN_DIR"
```

Each script's verification block prints `X passed, Y failed`. Surface every
script's output to the user.

Mid-chain, an intermediate script's `bootstrap --force` health check may WARN
about missing artifacts from a NEWER version ("expected mid-chain") — that is
normal, not a failure: a later migration in the chain installs them and the
final step re-validates everything. Only treat a script as failed on a nonzero
exit or a `✗` in its own verification block.

### Step 7: Report verification + next steps

If anything failed:

```
1. Inspect the diff: git diff
2. Restore from backup: .claude/settings.json.v0.3.bak (v0.3→v0.4 only)
3. Re-run /espalier-migrate (every script is idempotent)
```

On success:

```
Migration applied. Recommended next steps:

  1. Review the diff:
       git diff --stat
       git status

  2. Commit — stage EXACTLY the files each script reported touching (every
     script prints its touched paths, incl. backups and the settings-backup
     side-effect); never `git add -A`, which would sweep unrelated files
     into the migration commit:
       git add <each reported path>
       git commit -m "chore: migrate to Espalier vX.Y.Z"   # the version the chain just reached

  3. If you upgraded to v0.5.0, scan for drift that accrued before the upgrade:
       /espalier-doctor

  4. Try a real flow:
       /espalier feat: <some small feature>
```

## Flags (forwarded to scripts)

**v0.1→v0.2 (`migrate-v0.1-to-v0.2.sh`):**

| Flag | Effect |
|------|--------|
| `--dry-run` | Show actions only |
| `--yes` | Skip interactive prompt; defaults merge-strategy to `ask-later` |
| `--backfill=best-effort` | Try to recover historic commit SHAs via `git log --grep <slug>` |
| `--plugin-dir=<path>` | Override auto-detected plugin location |

**v0.3→v0.4 (`migrate-v0.3-to-v0.4.sh`):**

| Flag | Effect |
|------|--------|
| `--dry-run` | Show actions only |
| `--yes` | Skip apply confirmation prompt |
| `--rewrite-history` | Also rewrite text refs inside `espalier/changes/*/pipeline-state.md` bodies |

**v0.4→v0.5 (`migrate-v0.4-to-v0.5.sh`):**

| Flag | Effect |
|------|--------|
| `--dry-run` | Show actions only |
| `--yes` | Skip apply confirmation prompt |
| `--doctor-cadence=<val>` | `/espalier-doctor` cadence: `every-change\|weekly\|monthly\|manual` (default `weekly`) |
| `--plugin-dir=<path>` | Path to the espalier-engineering plugin checkout |

**v0.5.2→v0.5.3 (`migrate-v0.5.2-to-v0.5.3.sh`):**

| Flag | Effect |
|------|--------|
| `--dry-run` | Show the section that would be appended |
| `--yes` | Skip the apply confirmation prompt |

**v0.5→v0.6 (`migrate-v0.5-to-v0.6.sh`):**

| Flag | Effect |
|------|--------|
| `--dry-run` | Show actions only |
| `--yes` | Skip the apply confirmation prompt |
| `--plugin-dir=<path>` | Path to the espalier-engineering plugin checkout |

Backs up any customised pipeline skill on diff (`<file>.pre-v0.6.bak`), then
`bootstrap --force` installs the `espalier-grill` skill and refreshes the four
changed pipeline templates (which also date-prefix new change folders).
Idempotent — re-running detects an already-v0.6 install and no-ops.

**v0.6→v0.7 (`migrate-v0.6-to-v0.7.sh`):**

| Flag | Effect |
|------|--------|
| `--dry-run` | Show actions only |
| `--yes` | Skip the apply confirmation prompt |
| `--plugin-dir=<path>` | Path to the espalier-engineering plugin checkout |

Backs up any customised pure-copy pipeline file on diff (`<file>.pre-v0.7.bak`),
then `bootstrap --force` installs the `espalier-ask` skill and symlinks it.
Also patches CLAUDE.md + `espalier/agent.md` to mention `/espalier-ask` (the
bootstrap CLAUDE.md writer is append-once and never touches agent.md).
Purely additive — no pipeline change. Idempotent — re-running detects an
already-v0.7 install and no-ops.

**v0.7→v0.8 (`migrate-v0.7-to-v0.8.sh`):**

| Flag | Effect |
|------|--------|
| `--dry-run` | Show actions only |
| `--yes` | Skip the apply confirmation prompt |
| `--plugin-dir=<path>` | Path to the espalier-engineering plugin checkout |

Backs up any customised pure-copy pipeline file on diff (`<file>.pre-v0.8.bak`),
then `bootstrap --force` refreshes the three changed pipeline templates
(`pipeline.md`, `espalier`, `espalier-fix`) — adding the requirements approval
gate that stops both pipelines for explicit user sign-off before any code is
written (no-TTY runs auto-approve). No new skill, no pipeline stage added.
Idempotent — re-running detects an already-v0.8 install and no-ops.

**v0.8→v0.8.1 (`migrate-v0.8-to-v0.8.1.sh`):**

| Flag | Effect |
|------|--------|
| `--dry-run` | Show the sections that would be appended |
| `--yes` | Skip the apply confirmation prompt |

Appends a `## Change Impact Analysis` section to `harness-coder.md` and a
`## Runtime-Surface Review` section to `harness-reviewer.md` (both per-project
files a plugin update cannot reach). Patches each file independently and is
idempotent per file — re-running detects already-patched agents and no-ops. No
`--plugin-dir` needed (the patch appends inline text; the flag is accepted and
ignored for a uniform call signature).

**v0.8.1→v0.8.2 (`migrate-v0.8.1-to-v0.8.2.sh`):**

| Flag | Effect |
|------|--------|
| `--dry-run` | Show actions only |
| `--yes` | Skip the apply confirmation prompt |
| `--plugin-dir=<path>` | Path to the espalier-engineering plugin checkout |

Backs up any customised pure-copy pipeline file on diff (`<file>.pre-v0.8.2.bak`),
then `bootstrap --force` refreshes the two changed pure-copy files (`pipeline.md`,
`espalier-fix`) with the re-review fixpoint loop + `Reviewed-Diff` certificate
writes. Surgically appends a `## Re-review Rounds` section to the per-project
`harness-reviewer.md` and inserts the certificate check into the per-project
`pre-push-gate.sh` (graceful warn + manual snippet if the gate was customised past
the anchor). Idempotent — re-running detects an already-v0.8.2 install and no-ops.

**v0.8.2→v0.9.0 (`migrate-v0.8.2-to-v0.9.0.sh`):**

| Flag | Effect |
|------|--------|
| `--dry-run` | Show actions only |
| `--yes` | Skip the apply confirmation prompt |
| `--plugin-dir=<path>` | Path to the espalier-engineering plugin checkout |

Creates the new per-project files (security-standards + production-standards
rules, harness-security agent, espalier-security skill) with project-name +
tools-mode substitution, then `bootstrap --force` refreshes the pure-copy
pipeline/grill files + drift-helpers/wrapper/lookup hooks + copies scout-prompts
+ symlinks both new rules + the audit skill + runs the 37-check validation.
Surgically appends the security AND production sections to the per-project
`harness-coder.md` / `harness-reviewer.md` / `espalier-testing` SKILL /
`espalier-review` SKILL (and the Repo-Audit Mode section to a pre-fold
`harness-security.md`), inserts the secret/dependency scan + the cwd fail-closed
guard into `pre-push-gate.sh`, and patches CLAUDE.md + `espalier/agent.md`.
Idempotent — the already-v0.9.0 check requires all eleven artifacts present
(security + audit + production), so a crash mid-run is completed on re-run.

The `espalier-review` SKILL's `## Production-Readiness Checks` section is part of
that set. Fresh v0.9.0+ inits get it from the template; earlier builds of this
script declared the path but never wrote to it, so installs migrated by them lack
the section and `migrate-v0.9.2-to-v0.9.3.sh` refuses to patch them. Because the
section is in the already-v0.9.0 check, re-running this step on such an install
adds it rather than reporting "Nothing to do".

**v0.9.0→v0.9.1 (`migrate-v0.9.0-to-v0.9.1.sh`):**

| Flag | Effect |
|------|--------|
| `--dry-run` | Show actions only |
| `--yes` | Skip the apply confirmation prompt |
| `--plugin-dir=<path>` | Path to the espalier-engineering plugin checkout |

Creates `espalier/.espalier-config` if absent (extracted from the plugin's
bootstrap heredoc — single source of truth; an existing file is preserved),
then refreshes the three pure-copy pipeline files (`pipeline.md`,
`espalier/skills/espalier/SKILL.md`, `espalier-fix`) so their prose reads the
config keys. A customised file is backed up to `<file>.pre-v0.9.1.bak`.
Idempotent — config present + prose referencing it ⇒ no-op.

**v0.9.1→v0.9.2 (`migrate-v0.9.1-to-v0.9.2.sh`):**

| Flag | Effect |
|------|--------|
| `--dry-run` | Show actions only |
| `--yes` | Skip the apply confirmation prompt |
| `--plugin-dir=<path>` | Path to the espalier-engineering plugin checkout |

Backs up any customised pure-copy file on diff (`<file>.pre-v0.9.2.bak`), then
`bootstrap --force` refreshes the pure-copy skills + pipeline + scout-prompts +
hook templates, and two anchored surgical patches update the per-project
`pre-push-gate.sh` (active-change selection; portable test-count parse — the
substituted test command is read out of the old gate and carried forward).
Warn + manual snippet if the gate was customised past the anchors. Idempotent —
re-running detects an already-v0.9.2 install and no-ops.

The `^TEST_OUTPUT=` check assumes the gate runs ONE test command on the host, the
shape `hook-templates/pre-push-gate.sh` generates. A project whose gate was
customised at init to run tests another way (e.g. per-container `docker compose
exec`) cannot satisfy it: the surgical patch warns and prints a manual snippet,
and that one check reports `✗`. That is a template-shape mismatch, not a failed
migration — the guard it really enforces is that no `{test_command}` placeholder
was left unsubstituted.

**v0.9.2→v0.9.3 (`migrate-v0.9.2-to-v0.9.3.sh`):**

| Flag | Effect |
|------|--------|
| `--dry-run` | Show actions only |
| `--yes` | Skip the apply confirmation prompt |
| `--plugin-dir=<path>` | Path to the espalier-engineering plugin checkout |

Backs up `espalier-grill` + `espalier-review` (`<file>.pre-v0.9.3.bak`), refreshes
the pure-copy `espalier-grill` SKILL from the template, then re-splices the three
changed sections of the substituted `espalier-review` SKILL (frontmatter
description, `## Two Review Loops`, `## Production-Readiness Checks`), preserving
every init-substituted section — notably the `{detected convention}` checklist
line. Requires `python3`. Idempotent — re-running detects both v0.9.3 markers and
no-ops.

Fails closed with `ERROR: install missing section` if the installed
`espalier-review` lacks `## Production-Readiness Checks`. That means the v0.9.0
step never ran (or ran from a build predating its review-skill patch) — re-run the
v0.9.0 step, which is idempotent and adds the section.

**v0.9.3→v0.9.4 (`migrate-v0.9.3-to-v0.9.4.sh`):**

| Flag | Effect |
|------|--------|
| `--dry-run` | Show actions only |
| `--yes` | Skip the apply confirmation prompt |
| `--plugin-dir=<path>` | Path to the espalier-engineering plugin checkout |

Backs up `harness-security.md` + `espalier-security` SKILL (`<file>.pre-v0.9.4.bak`),
then replaces the `description:` frontmatter line of each from the v0.9.4 template
(substituting this project's name into the skill's), and re-splices the two changed
body spans of the agent (P0 rubric, repo-audit delta 5). Requires `python3`.
Idempotent — re-running detects both v0.9.4 markers and no-ops.

Frontmatter is edited **line-wise, never rewritten**: an install created in
`inherit` tools-mode has had its `tools:` line stripped, and copying the template's
frontmatter would silently reintroduce it. The verification asserts the install's
original tools-mode is preserved.

A body span whose anchor the project has customised away is left untouched and
reported **warn-only** (not `✗`), because the v0.9.4 wording is a clarity
improvement, not a behaviour change. The script still exits 0 and still applies
every span it could match.

**v0.9.6→v0.10.0 (`migrate-v0.9.6-to-v0.10.0.sh`):**

| Flag | Effect |
|------|--------|
| `--dry-run` | Show actions only |
| `--yes` | Skip the apply confirmation prompt |
| `--plugin-dir=<path>` | Path to the espalier-engineering plugin checkout |

Backs up `espalier/hooks/pre-push-gate.sh` (`<file>.pre-v0.10.0.bak`), then rewrites
its build / lint / test spans from the v0.10.0 template, **preserving the commands
this project substituted at init**. Requires `python3`.

Each span is handled independently. A gate can be half-migrated — running the v0.9.2
step against a v0.10.0 plugin re-splices only the test span, leaving `run_tests` with
old build/lint — so the idempotency guard requires all three functions, and a span
already function-shaped is skipped rather than re-read. The test command is never
read back from `TEST_OUTPUT=$(run_tests 2>&1)`; that yields the function name.

A gate customised at init past the template shape (e.g. a Docker-first gate running
each suite in its own container) is **left completely untouched**, reported with the
manual change list, and the script exits 0. It is never mangled. The decline is
recorded once in `espalier/.migrations-skipped` (`v0.10.0-gate: customised,
manual port needed`), so detection reports the version as handled (manual)
instead of re-proposing the patch every run.

**v0.10.0→v0.11.0 (`migrate-v0.10.0-to-v0.11.0.sh`):**

| Flag | Effect |
|------|--------|
| `--dry-run` | Show actions only |
| `--yes` | Skip the apply confirmation prompt |
| `--plugin-dir=<path>` | Path to the espalier-engineering plugin checkout |

Rebuilds `espalier/hooks/pre-push-gate.sh` from the v0.11.0 template, preserving
the three command bodies substituted at init (`run_build` / `run_lint` /
`run_tests` — single commands or multi-line blocks). Blocking paths now exit 2
with the reason on stderr — the Claude Code PreToolUse contract; the old exit-1
gate never actually blocked. A customised gate is left untouched, recorded in
`espalier/.migrations-skipped` (`v0.11.0-gate: customised, manual port needed`)
and the exact manual contract is printed. Overwrites both wrappers and
`pipeline.md` + the 8 pure-copy pipeline skills from templates
(backups `<file>.pre-v0.11.bak`), patches `check-layer-boundaries.sh` to
exit 2 + stderr via anchored sed, appends `, Write` to the reviewer/security
agents' `tools:` lines (inherit-mode installs — no `tools:` line — are logged
and skipped, never failed), and refreshes `espalier-review` /
`espalier-security` SKILL.md re-substituting `{project}` with the name
recovered from the installed file (recovery failure → skip marker + manual
instructions). Requires `python3`. Idempotent — re-running detects the
v0.11-shaped gate (or its skip marker) plus the verdict-gate line and no-ops.

**v0.11.0→v0.12.0 (`migrate-v0.11.0-to-v0.12.0.sh`):**

| Flag | Effect |
|------|--------|
| `--dry-run` | Show actions only |
| `--yes` | Skip the apply confirmation prompt |
| `--plugin-dir=<path>` | Path to the espalier-engineering plugin checkout |

The v0.12.0 change is confined to one pure-copy file — the grill skill gains
Step 1.5, the rules/wiki blind-spot pass — so this migration is a single
backup-and-refresh of `espalier/skills/espalier-grill/SKILL.md` from the v0.12.0
template (backup `<file>.pre-v0.12.bak`). It refuses to run against a stale
plugin whose grill template lacks Step 1.5, and it never touches user-customised
files (the grill skill is plugin-owned, copied verbatim, never substituted).
Verifies the refreshed skill carries Step 1.5 and still cross-checks
`espalier/rules/` + `espalier/wiki/`. Idempotent — re-running detects Step 1.5
in the installed grill skill and no-ops. No `python3` needed.

## Anti-Patterns

- NEVER skip the dry-run preview — users should see what will change before applying.
- NEVER pass `--yes` to any script without asking the user first.
- NEVER reorder: v0.1→v0.2 before v0.3→v0.4 before v0.4→v0.5. Each migration
  assumes the previous layout.
- NEVER modify a migration script from this skill — if a bug surfaces, file an
  issue against the plugin.
