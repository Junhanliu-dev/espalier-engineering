# Ponytail v4.10 → Espalier — second transplant, gap plan v1

Status: **implemented as v0.28.0** (2026-09-15, on `feat/v0.26-turn-economy`
after v0.27.0). Decisions taken at the owner's gate: marker word `ceiling:`;
Track C ships as a reference file; Track F skipped (recorded in
`docs/deferred-items.md`); scope A + B + D + E. The doctor notify line named
under Track A was dropped — the stats ledger's blame date covers it. Source: [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail)
at `e3ba2aa` (v4.10.0, 2026-09-14, MIT). First transplant: v0.13.0
(2026-07-17) — the coder's Solution Selection Ladder and the reviewer's
Minimalism Review. Owner rules unchanged: conventions outrank brevity
(`harness-coder.md` → "Convention beats brevity, always"), no hard budgets,
every lever with "why quality holds".

"All the agents for this repo" = the files Espalier generates and loads as an
agent's system prompt in a target project: `harness-coder`, `harness-reviewer`,
`harness-security`, and the orchestrator (the `/espalier*` skills read by the
main session). Ponytail reaches its subagents with a `SubagentStart` hook
because its ruleset lives outside the agent definitions; Espalier does not
need that hook — each agent's instruction file IS the injection point
(`.claude/agents/*.md` symlink, `.codex/agents/*.toml` `developer_instructions`,
`.github/agents/*.agent.md` body). Reach is decided by which agent file
carries which text, and that is what this plan assigns.

## 1. Ponytail v4.10 in one paragraph

One persona skill (`skills/ponytail/SKILL.md`, 130 lines): a seven-rung
ladder run *after* understanding the problem (YAGNI → already in this
codebase → stdlib → native platform → installed dep → one line → minimum
code), a rules list (no unrequested abstractions, deletion over addition,
fewest files, edge-case-correct stdlib option, mark real-corner shortcuts
with a `ponytail:` comment naming ceiling + upgrade path), an output shape
(code first, ≤ 3 lines "skipped X, add when Y"), three intensities
(lite/full/ultra), and a "when NOT to be lazy" floor (trust boundaries,
data-loss handling, security, accessibility, understanding, hardware
calibration, one runnable check per non-trivial change). Five one-shot
sub-skills: `-review` (diff, tags `delete:/stdlib:/native:/yagni:/shrink:`,
ends `net: -N lines`), `-audit` (same, repo-wide, ranked), `-debt` (grep the
`ponytail:` markers into a ledger, flag `no-trigger`), `-gain` (benchmark
scoreboard, explicitly never a per-repo number), `-help`. Distribution:
three Node hooks (SessionStart injects the mode-filtered ruleset + writes a
flag file; SubagentStart re-injects into every Agent-tool spawn;
UserPromptSubmit tracks `/ponytail <level>`), 20 host adapters, a compact
`AGENTS.md` copy for instruction-only hosts, `docs/platform-native.md` (a
"you think you need X → the platform has Y" table for HTML/CSS/JS/Swift/
Node/Python/SQL), and an agentic benchmark (real headless sessions, source
LOC of the diff vs a no-skill baseline, plus a deterministic safety tier).

## 2. What Espalier already carries (verified by reading the templates)

| Ponytail piece | Espalier v0.27.0 | Where |
|---|---|---|
| Ladder rungs 2–7 | Solution Selection Ladder, five convention-bounded rungs; runs after specs/references/blast radius | `harness-coder.md` § Solution Selection Ladder; `espalier-coding.md` § Solution Selection |
| "Ladder after understanding, never instead" | verbatim in the ladder intro and Before-Writing step 7 | `harness-coder.md` |
| Edge-case-correct option between equals | rung 5: more correct → more readable → shorter | `harness-coder.md` |
| Rules: no single-impl abstraction, no config nothing sets, no scaffolding | rung 1 | `harness-coder.md` |
| Output: name what was skipped | coding-report `- Notes:` one line per deliberate non-build; report hygiene | `harness-coder.md` |
| `/ponytail-review` tags | Minimalism Review `delete:/stdlib:/native:/yagni:`, P2/P3, new-dependency P1, convention tie-break, "Minimalism: lean" | `harness-reviewer.md` § Minimalism Review; `espalier-review.md` Leanness |
| "Never simplify away trust boundaries / data-loss handling / security" | the ladder floor + Security-Aware / Production-Aware Coding; reviewer Production-Readiness tiers | `harness-coder.md`, `harness-reviewer.md` |
| Root-cause over symptom (on fix rounds) | Fix the Class, Not the Instance — sibling enumeration, `### Class Sweep`, `[class-sweep]` P1 | `modes/fix-round.md` |
| "ONE runnable check" | STRONGER: interface + failure-mode + abuse tests are Stage 3 duties, judged by the panel | `harness-coder.md`, `espalier-testing.md` |
| `/ponytail-audit` | STRONGER: `/espalier-simplify` — evidence ladder, consumer map, proof record, cuts filed as refactor changes the panel runs | `espalier-simplify.md` |
| Over-build measurement | coder eval `overbuild` judge field, `coder-04-overbuild-trap`; review eval `clean-02-minimal-guard`, `rule-newdep-06` | `eval/coder`, `eval/review` |
| Always-on copy for instruction-only hosts | `AGENTS.md` / `copilot-instructions.md` `## Espalier` section → rules; the ladder is read inline where a host has no subagents | bootstrap wiring |

Nothing in this table needs re-transplanting. The July borrow took the
ladder and the review lens; what has grown in ponytail since is around them.

## 3. Gap analysis

| Ponytail v4.10 feature | Espalier v0.27.0 | Verdict |
|---|---|---|
| **`ponytail:` ceiling marker + `/ponytail-debt` ledger** — a deliberate shortcut with a known ceiling is marked in code with its ceiling and upgrade trigger; a one-shot skill harvests every marker and flags the ones with no trigger | The coder records "what I deliberately did NOT build" in coding-report Notes — per change, under `espalier/changes/`, never in the code, never harvested. `grep -rn "ceiling\|upgrade path" templates/` = 0 outside the simplify skill's unrelated use. `/espalier-simplify` hunts *accidental* complexity; a deliberate ceiling is invisible to it | **missing — the largest gap.** Track A |
| **Rung 1, "does this need to exist at all?"** | Coder rung 1 is deliberately narrower ("not in requirements.md → don't build it"; WHAT is settled at Stage 1/2 and never re-litigated). The grill probes scope in/out, wiki duplication (→ "reuse the existing capability" out-line) and rule collision — but has no signal for a requirement that *names a mechanism* the outcome does not need (a cache class, a new picker lib, a config surface) | **partial.** The rung belongs at Stage 1, where WHAT is decided. Track B |
| **`docs/platform-native.md`** lookup table | Rung 4 says "stdlib, then native platform feature, then installed dependency" with three examples; no reference | **missing.** Generic knowledge, not project convention, consulted only when conventions are silent. Track C |
| **Bug fix = root cause, grep every caller, guard the shared function once** | Fix lane: grill `diagnosis` mode confirms the root cause; Change Impact Analysis step 1 enumerates "other callers"; class sweep runs on fix ROUNDS. The first fix-lane coder spawn has no line saying *where* the fix lands (the shared function, not the caller the ticket names) | **partial.** One clause. Track D |
| **`shrink:` tag** (same logic, fewer lines, show the shorter form) | Reviewer tags stop at `yagni:` | **small gap**, with a ping-pong risk against the Readability Review (`nesting:`). Track E |
| **Hardware calibration floor** ("leave the knob; a clock drifts") | not in the ladder floor | **niche;** one clause in the floor. Track E |
| Intensity levels lite/full/ultra; `/ponytail <level>`; flag file; SessionStart/UserPromptSubmit hooks | none | **reject.** The ladder is a rule, not a mood; `ultra` ("challenge the requirement in the same breath") contradicts "never re-litigate WHAT"; per-session mode state is the nondeterminism the v0.13 decision ruled out |
| SubagentStart injection | not needed (see preamble) | no gap |
| "Complex request? ship the lazy version and question it in the same response" | Stage 1/2 contract + `### Deviations` + `- BLOCKED-ON-REQUIREMENT:` (v0.27) | **reject** — a different model, already solved |
| `/ponytail-review` ends `net: -N lines possible` | "There is no count either way" (v0.13 decision) | **reject** — a count invites finding quotas |
| `/ponytail-gain` scoreboard; agentic LOC benchmark | `espalier-stats.sh` reports rounds / rollbacks / deviations, never lines; coder eval judges `overbuild` 0/1 by LLM, no deterministic LOC | **optional information only.** Track F |
| `/ponytail-help` | README command table | no gap |

## 4. Tracks

Every track is contract-equal: no gate, sentinel, round cap, rubric or
escalation path changes. Text lands in the agent file whose role it belongs
to — builder text in the coder, judge text in the reviewer, nothing in the
security auditor (a control is never `yagni:`; the auditor's scope already
excludes over-building, and ponytail itself puts security under "never
lazy").

### Track A — Ceiling markers and their ledger (coder, reviewer, stats, simplify, coding-standards)

**Coder (`harness-coder.md`, ladder rung 5 + Editing Discipline).** A
deliberate simplification that cuts a *real* corner with a *known* ceiling —
a global lock, an O(n²) scan, a naive heuristic, an in-memory cache with no
eviction — gets ONE plain-line comment at the site, in the project's comment
syntax, in a fixed shape the tools can grep:

```
# ceiling: global lock; per-account locks when contention shows in p95
```

`ceiling: <the limit>; <the trigger to revisit>`. This is exactly the one
comment the v0.21.1 comment budget allows ("a constraint the code cannot
show"), so it adds no comment-density conflict — the shape is added to
`coding-standards.md` → Comments & Docstrings as the named case. A skipped
*abstraction* (the yagni case) stays in coding-report Notes as today; a
marker is for a shortcut that will stop holding, not for a thing not built.
The same line goes to coding-report Notes with its `path:line`.

**Reviewer (`harness-reviewer.md`, Minimalism Review).** Two advisory rows,
P3, tie-break unchanged: `[ceiling]` — a Notes-listed shortcut with a real
ceiling and no marker at the site, Fix = the one-line marker; `[no-trigger]`
— a marker that names a limit but no trigger, Fix = the trigger. Never a P1;
never counted.

**Ledger.** No new skill. `espalier-stats.sh` gains a `ceilings:` section:
`grep -rnE '(#|//|--|<!--) ?ceiling:'` over tracked source (excluding
`espalier/`, generated paths from `grep-only-paths:`), count, count with no
`;` trigger, oldest by `git log -1 --format=%as -L`. `/espalier-simplify`
step 2 reads the markers as leads: a ceiling whose trigger has fired is
either a cut (the shortcut's consumer is gone) or an upgrade candidate
(files as a normal change) — the survey already has the evidence ladder for
that. `/espalier-doctor --full` lists markers older than the doctor cadence
with no owner change, notify-only.

**Why quality holds.** Today a deliberate shortcut is recorded in a change
folder the next coder never opens; the reviewer confirms it once and it is
gone. A marker at the site is read by the next coder who touches the line
and by the simplify lane's grep — the shortcut keeps its upgrade path
attached to the code it constrains. Nothing here trims anything: the marker
is only written where the coder already chose the shortcut under the
ladder's rung 5.

**Name.** `ceiling:` rather than `ponytail:` — Espalier owns its vocabulary
and the word says what the line is. Owner's call; keeping `ponytail:` buys
interop with `/ponytail-debt` for a team that runs both, at the cost of a
brand word in project source. Either way one constant in three files.

### Track B — Grill signal: over-specified mechanism (orchestrator, Stage 1)

Add one row to the grill's Step 1 signal table:

| Signal | Example |
|---|---|
| Over-specified mechanism | the input names HOW where a documented capability, a stdlib/native feature, or nothing at all would meet the WHAT — "add a caching layer for X" when X is read once per request |

Counted like the other signals (it can floor a `skip` to `light`); Step 1.5
already cross-references `wiki/` and `rules/` and is where the alternative
is found; the resolution lands exactly like a resolved collision — a `##
Scope Definition` out-line ("no cache class; `lru_cache` on the fetch —
revisit when p95 > N") or an Acceptance Criteria line if the requester keeps
the mechanism (their call, no re-arguing, same as ponytail's "user insists →
build it").

**Why quality holds.** This is rung 1 placed where Espalier decides WHAT.
The coder stays forbidden from re-litigating; the human decides at the gate
with the alternative written down; the eval already has the fixture pattern
(`grill` suite, planted signals with a judge).

### Track C — Platform-native reference (on-demand, coder)

Ship `docs/platform-native.md` (MIT, attributed at the top) as
`espalier/skills/espalier-coding/references/platform-native.md`, pure copy,
never scout-filled. Rung 4 of the ladder names it: "conventions silent on
the mechanism → check the reference for the platform before choosing;
stdlib → native → installed dep". Not auto-loaded — read at rung 4 only,
which keeps the quality invariant's "when inputs arrive" rule (≈ 230 lines,
loaded on the one decision that needs them, never into the reviewer).

**Why quality holds.** Rung 4 today relies on the model recalling that
`structuredClone` / `<input type="date">` / `CHECK (price > 0)` exist; the
table turns a recall into a lookup. The tie-break is unchanged: a
convention-named mechanism (rung 3) still beats every row.

### Track D — Where a fix lands (coder, fix lane)

One clause in Change Impact Analysis step 1 (read by every coder spawn,
first spawn included): "A bug report names one path. The fix lands where
every caller routes through — one guard in the shared function is the
smaller diff AND the whole fix; a guard on the reported path alone leaves
each sibling caller broken and returns as a fix round." The fix-round class
sweep keeps its own (wider) duty; this line prevents the instance-only fix
on round 1.

### Track E — `shrink:` tag and the calibration clause

Reviewer Minimalism Review gains `shrink:` — same logic, fewer lines, the
shorter form shown in Fix — P3 only, valid ONLY when the shorter form would
not draw a Readability `nesting:` / `structure:` row (clarity beats brevity
is the ladder's own tie-break; a `shrink:` that compresses is invalid). The
ladder floor gains: "a physical-world calibration knob (clock drift, sensor
offset, timing constant) is never trimmed to the ideal value". Both are one
line; both are advisory.

### Track F — Information-only metrics (optional)

`espalier-stats.sh`: per completed change, `git diff --shortstat
<Base-Ref>..HEAD -- . ':(exclude)espalier/' ':(exclude)<test paths>'` →
`net source lines: n=… median=…` next to the rounds distribution. Coder
eval: a deterministic `loc` column (source lines of the diff, tests
excluded) in `run.sh` output beside the judge's `overbuild`. Never a gate,
never a counterfactual "you saved N" (ponytail's own honesty rule: the
unbuilt version was never written).

## 5. Rejected, with the reason recorded

- **Intensity modes and mode hooks** — session state outside the audit
  trail; `ultra` re-litigates WHAT; the v0.13 decision.
- **"Ship the lazy version and question in the same response"** — v0.27's
  Deviations channel and the blocked sentinel are the Espalier answer.
- **One-check test minimum** — would weaken the Stage 3 test duty.
- **`net: -N lines` in review output** — a count is a quota in disguise.
- **`/ponytail-audit` as a skill** — `/espalier-simplify` is the stronger
  form; Track A feeds it the deliberate ceilings it could not see.
- **`/ponytail-gain`** — benchmark medians from another repo say nothing
  about this one; Track F keeps the honest per-repo number only.

## 6. Migration mechanics (if the tracks are approved as v0.28.0)

Per-project files touched: `espalier/agents/harness-coder.md` (ladder rung
5 marker rule, floor clause, Change Impact clause), `harness-reviewer.md`
(`shrink:`, `[ceiling]`, `[no-trigger]`), `espalier/rules/coding-standards.md`
(the marker as the named comment case), `espalier/skills/espalier-grill/SKILL.md`
(signal row — pure copy, plugin-owned), `espalier-simplify/SKILL.md` (pure
copy), `espalier/hooks/espalier-stats.sh` (pure copy), new
`espalier/skills/espalier-coding/references/platform-native.md` (pure copy).

- `scripts/migrate-v0.27.0-to-v0.28.0.sh` in the v0.27 shape: pure-copy
  refresh with `.pre-v0.28.bak` on diff; anchored edits extracted from the
  plugin templates at run time (anchors: `5. **Only then:**` block end,
  `The ladder is never a licence`, `4. **Record the blast radius.**`,
  `- \`yagni:\``, coding-standards `- Default to NO comment:`); a
  customised file missing its anchor → `espalier/.migrations-skipped`.
- `/espalier-migrate` chain step 38; probe `NEEDS_V0280_PATCH` =
  `! grep -qF 'ceiling:' espalier/agents/harness-coder.md`.
- Bootstrap check 70 `ceiling-ledger` (grep the marker rule in coder +
  reviewer + stats section + the reference file); `test-bootstrap.sh`
  totals 60/65/70.
- Evals: coder fixture `coder-NN-ceiling-marker` (a task whose leanest
  correct shape carries a known ceiling → marker present, trigger named;
  judge field `ceiling_marked`); review fixtures `rule-shrink-NN` (a
  planted 8-line loop with a 1-line stdlib equal → one `shrink:` P3) and
  `clean-03-shrink-vs-readability` (a longer form that is the readable
  one → zero `shrink:` rows, the FP guard); grill fixture with a planted
  over-specified mechanism. Baseline A/B under today's model before any
  attribution (`eval-baseline-attribution`).
- CHANGELOG 0.28.0, `docs/migrating-v0.27-to-v0.28.md`; README command
  table unchanged (no new command).

## 7. Open decisions for the owner

1. Marker word: `ceiling:` (recommended) or `ponytail:` (interop).
2. Track C ships a third-party table into every install (≈ 230 lines on
   disk, loaded only at rung 4) — accept, or link to the upstream doc
   instead and let the coder fetch nothing.
3. Track F at all — the stats hook has stayed line-count-free on purpose.
