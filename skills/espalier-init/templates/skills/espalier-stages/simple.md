# /espalier and /espalier-fix — Simple mode (`--simple`)

> Loaded by either lane's router when the invocation carries `--simple`, at
> Stage 1 entry (fix lane: before Stage 0), and kept resident for the whole
> run — it OVERRIDES the stage files wherever it says so and is silent
> everywhere else. `espalier/pipeline.md` stays the contract for the stages
> that run. Verbatim procedure — read once.

Simple mode is the human-review lane: the pipeline grills, writes the spec,
waits for approval, codes, reviews, tests — and then STOPS with the code
uncommitted in the working tree for a human to read and commit by hand. It
leaves no audit trail: the only files it writes outside the source tree live
in one scratch folder that Approve deletes. Nothing is committed, projected,
pushed, or opened as a pull request, and nothing under `espalier/` changes
except that folder.

### Pre-checks (both lanes — before Stage 0, before any folder is created)

```bash
. espalier/hooks/drift-helpers.sh
[ "$(interactivity_mode)" = unattended ] \
  && { echo "simple mode is a human-review lane — refused under CI / ESPALIER_UNATTENDED / ESPALIER_LOOP / ESPALIER_HEADLESS"; exit 1; }
DIRTY=$(git status --porcelain -- . ':(exclude)espalier/')
if [ -n "$DIRTY" ]; then
  echo "simple mode refused: the tree is dirty outside espalier/ — commit or stash first:"
  printf '%s\n' "$DIRTY"
  exit 1
fi
ESP_DIRTY=$(git status --porcelain -- espalier/)
[ -n "$ESP_DIRTY" ] && echo "note: espalier/ is dirty ($(printf '%s\n' "$ESP_DIRTY" | wc -l | tr -d ' ') path(s), another in-flight change's records) — excluded from the review diff; continuing"
```

Three rules, in order. Unattended → refuse: nobody is there to give the
final approval that deletes the folder, and auto-approving a spec is the
opposite of what this mode is for. Dirt OUTSIDE `espalier/` → refuse: the
reviewer judges `git diff <Base-Ref>`, so a human's own uncommitted edits
would be reviewed as the coder's work and the uncommitted result would be a
mix of both — the point of the mode is that `git status` at the end IS the
change. Dirt INSIDE `espalier/` → one line, continue: those records are
excluded from the review diff and never touched here.

### The folder and the state file

The run's folder is `espalier/.simple/{slug}/` — `{slug}` derived exactly as
the lane derives it (`{YYYY-MM-DD}-{kebab}`; `--slug` literal in the fix
lane). `espalier/.simple/` is gitignored (init writes the entry; the v0.30
migration adds it to older installs) — a human's `git add .` after the run
cannot sweep it in. Create it from `espalier/changes/_template/` as the lane
would create a change folder, then write the Status block with two extra
lines:

```markdown
## Status
- Current Stage: 1
- Status: IN_PROGRESS
- Mode: simple
- Type: {feat|fix|refactor|docs}
- Base-Ref: {git rev-parse HEAD}
- Started: {ts}
…
```

`- Mode: simple` is what every later read keys off. `- Base-Ref:` is written
at CREATION, not at Stage 3: nothing is ever committed in this mode, so
HEAD-at-start is the anchor for the whole run — the reviewer's diff, the
exit gate's scope, the fix lane's regression check at the pre-fix tree.
Never overwrite it. Resumption reads the same lines: a tail-matching
`IN_PROGRESS` state file under `espalier/.simple/*/` resumes at its
`Current Stage:` exactly as a change folder would; a bare `/espalier --simple`
(or `/espalier-fix --simple` with no bug text) resumes the single in-flight
simple run, or lists several and asks.

**The path rule (stated once).** Every stage file names paths under
`espalier/changes/{type}/{slug}/`. In simple mode READ EVERY ONE OF THEM as
`espalier/.simple/{slug}/` — the context pack's `- Verify:` line, the
`CONTEXT PACK:` / `coding-report.md` / `review-record.md` lines in every
spawn prompt, `coding-log/`, `requirements.md`. Helpers that take a `DIR`
argument are called with that folder: `report_archive`, `exit_gate`,
`req_shape_check`, `deviations_list`, `open_question_append`,
`regression_verify`, `simple_brief`. Helpers that take `TYPE SLUG` and
build the `espalier/changes/` path themselves are NOT called in this mode —
`record_commits`, `drift_index`, `stage85_drift`, `delivery_brief`,
`backlink_all`, `certificate_write` — each belongs to a step the skip list
below removes.

**FILED skeletons are never adopted.** A simple run that tail-matches a
`Status: FILED` skeleton under `espalier/changes/` (a map slice, a simplify
cut, a partial fix's root-cause feat) says so in one line
(`note: a FILED skeleton matches this slug — a simple run never adopts it;
run /espalier <requirement> without --simple to adopt`) and continues as a
plain simple run with its own folder. Adoption writes into the skeleton's
tracked folder, which this mode never does.

### What runs, and the overrides

| Stage | Simple mode |
|-------|-------------|
| 0 pre-flight (drift / conventions / doctor) | NOT RUN. No prompt, no `.drift-report.md` line, no promotion. The gardener rota owns maintenance; a run that writes nothing has nothing to maintain. |
| 0 auto-link (fix lane) | RUNS READ-ONLY — see below. |
| 1 grill + spec | Unchanged. `requirements.md` + `requirements-notes.md` in the simple folder; `--no-grill` still honoured. |
| 2 spec review | Unchanged (full lane). The fix lane has no Stage 2, as ever. |
| Approval gate | ONE question — see below. |
| 3 coding | Unchanged except the `SIMPLE MODE:` prompt line and the no-commit rule — see below. Exit gate (`exit_gate DIR files`) unchanged. |
| 4 review | Reviewer ONLY, single-record gate — see below. Fixpoint loop, `FIX ROUND {n}` re-spawn, `max-code-rounds` cap, `ROUND {n} FAIL` snapshot rows, `Review Rounds:` numerators: unchanged. |
| 5 / 6 | Rows only: `| 5 | SKIPPED | {ts} | simple: no security contract |` and `| 6 | SKIPPED | {ts} | simple: reviewed at Stage 4 |`, `Current Stage:` 5 → 6 → 7 in one bash — the stage integer stays monotonic for `espalier-stats.sh`. |
| 7–10 | REPLACED by the Final Gate below. |

**Not run, ever, in this mode** (each would write outside the folder or
record a run that leaves no trail): Stage 0 pre-flight and Convention
Promotion; `certificate_write` (its only reader is the push gate); the Stage
4 Post-Review entirely — `drift_index`, `append_convention`, `mark_stale`;
the Stage 7 wiki sweep; `record_commits`; every `espalier-pr.sh`
subcommand; Stage 8 CI, the Stage 8.5 drift check, Stage 9 deploy;
`delivery_brief`; the Completion projection, the findings digest and map
Spawned-Changes update, the simplify retired-surface flagging, the
`## Settled for next time` append; the fix lane's `backlink_all`, the
commit-index self-heal, and the PARTIAL_FIX skeleton filing (a partial fix
says so in the Final Gate brief and nothing is filed). The session-boundary
stops are not offered either — the run is one session by design.

#### Fix lane Stage 0 — read-only auto-link

Run 0.1–0.4 as written: blame, the tiered reverse lookup, the linked
context read (the causing change's `requirements.md`, `coding-report.md`,
`review-record.md` — the diagnosis is better for it), and the `caused_by:`
frontmatter — written into the SIMPLE folder's `requirements.md` only. Two
writes are dropped: `_cache_append` (Layer 1/2 self-heal of
`espalier/.commit-index.tsv` — pass `--no-index` semantics for the write
half: read the cache if present, never append) and anything into the
causing change's folder. The `--caused-by` flag works as usual. Record
`| 0 | PASSED | {ts} | Auto-linked (read-only) to {N} change(s): … |`.

#### The Requirements Approval Gate — one question

Present the summary exactly as the lane's gate does (decisions first, then
goal and criteria, then scope). Write the context pack in the same turn
(`stages/3-coding.md` → Context Pack, paths under the simple folder; its
`- Verify:` line is `exit_gate espalier/.simple/{slug} {test files}`). Then
ask ONE question:

```
Requirements are written and reviewed. Nothing has been coded yet.
Simple mode: the result stays uncommitted for your review; nothing is
pushed. Approve to start Stage 3 (Coding)?

Options:
  1. Approve — proceed to coding.
  2. Edit    — tell me what to change; I revise requirements.md and re-ask.
  3. Abort   — stop here; the folder stays (Status: ABORTED).
```

No Push-Target, Deploy-Target, Session-Boundary, or maintenance (3b)
question — none of those stages run. The lane's Edit / Abort semantics are
unchanged; the Stage 1 escalation gate of the fix lane still runs first
(migrating to the full lane keeps `--simple`).

#### Stage 3 — the coder never runs git

Add this line to EVERY coder prompt of the run (first spawn, continuation,
fix round, parallel part), directly under the `CONTEXT PACK:` line:

```
SIMPLE MODE: do NOT run git at all — no add, no commit, no stash. Commit
Discipline is suspended; write `- Commits: none — simple mode` and one
`- Commit:` suggested subject per unit in your report.
```

Replace the prompt's `COMMITS:` paragraph with that line (the coder's
harness-coder.md → Simple Mode section says the same). Under PARALLEL
DISPATCH the orchestrator commits NOTHING after the wave — the parts'
`- Commit:` lines are kept in the combined report as suggestions. The
`FIX ROUND {n}:` re-spawn line drops its `commit each class as its own
commit (…)` clause. Everything else in `stages/3-coding.md` applies: the
exit gate on every return, handoff and blocked sentinels, `report_archive`
before every re-spawn, the fix lane's `regression_verify` (Base-Ref is the
pre-fix tree, as it must be).

#### Stage 4 — reviewer only

Spawn `harness-reviewer` ALONE each round with the `stages/4-panel.md`
review prompt, two lines changed:

- `COMMITS:` → `COMMITS: none (simple mode) — the change is the working
  tree: git diff <Base-Ref> -- . ':(exclude)espalier/'` (paste the
  Base-Ref); the `commits:` P3 row does not arise.
- Add after it: `SIMPLE MODE: there is no security auditor this run. Your
  verdict is the only gate — keep your Security-Aware checks at full
  strength, but write no security-record.md.`

No `harness-security` spawn, no `security-record.md`, no contract. The
gate read is SINGLE-record: `V=$(grep '^VERDICT:' espalier/.simple/{slug}/review-record.md | tail -1)`,
written THIS round (`round={n}`), verdict word `PASS` / `PASS_WITH_FIXES`
with `p0=0 p1=0` → advance; `FAIL` or any P0/P1 → the fixpoint loop exactly
as `4-panel.md` steps 2–4 run it for one agent (snapshot row with one
bracket, cap check BEFORE re-spawn, `report_archive`, `FIX ROUND {n}:`
re-spawn minus its commit clause, numerators updated); `ESCALATION_REQUIRED`
→ the escalation protocol, never advance. On PASS: the `| 4 | PASSED |` row
with `deviations: {n}` and the `deviations_list` print — then STOP there.
No `certificate_write`, no Post-Review drift or convention index, no
boundary read. Write the two SKIPPED rows for Stages 5/6 and go to the
Final Gate.

### The Final Gate (replaces Stages 7–10, both lanes)

Set `- Current Stage: 7` (the row `| 7 | IN_PROGRESS | {ts} | simple: final gate |`).
Then, in ONE bash with no agent in flight:

```bash
. espalier/hooks/drift-helpers.sh
DIR="espalier/.simple/${SLUG}"
exit_gate "$DIR"            # the whole tree, once more — green required; red → back to the coder (Stage 3 exit-gate path), never to the human
simple_brief "$DIR"         # writes $DIR/simple-brief.md, prints its path + one count line
```

`simple_brief` ASSEMBLES, never authors: the requirement summary and
acceptance criteria from `requirements.md`; the files changed from
`git status --porcelain -- . ':(exclude)espalier/'` (this IS the change —
Base-Ref has not moved); the coding report's `Files created / modified /
Test files` lines; every `- Commit:` suggested subject from the current
report and `coding-log/` (the human's commit messages, ready to use); the
`### Deviations` block (or `none`); the review record's last `VERDICT:`
line; the fix lane's last `- REGRESSION_VERIFIED:` line when present; the
ROUND / HANDOFF / BLOCKED / ESCALATED / RESUMED rows of the Stage History.
A section with no source is one `none` line.

Present the brief, then ask with `AskUserQuestion` — exactly three options:

```
Review passed and the exit gate is green. The change is in your working
tree, uncommitted; espalier/.simple/{slug}/ holds the run's records.

Options:
  1. Approve         — delete espalier/.simple/{slug}/; I commit nothing —
                       you review and commit by hand.
  2. Request Changes — tell me what to change; a fresh coder fixes it, the
                       reviewer re-reviews, I re-present.
  3. Abort           — leave the code AND the folder in place; stop.
```

- **Approve** → `rm -rf "espalier/.simple/${SLUG}"` (this deletion is the
  design: the folder was scratch from the first line), then print:
  `done — code is uncommitted; review and commit by hand` followed by the
  files changed and the suggested commit subjects from the brief (the
  brief is gone with the folder, so print them NOW). Nothing else: no
  commit, no projection, no PR, no stats row.
- **Request Changes** → the user's note becomes a `FIX ROUND {n}:` coder
  prompt (it counts against `max-code-rounds` — check the cap BEFORE the
  spawn exactly as Stage 4 does; at the cap escalate instead), then one
  reviewer round (Stage 4 above), then the exit gate + brief + this
  question again. Row: `| 7 | CHANGES REQUESTED | {ts} | {≤80 chars of the note} |`.
- **Abort**, or an escalation at the round cap anywhere in the run →
  `- Status: ABORTED` (`ESCALATED`), the matching Stage History row, and
  ONE line: `stopped — the code is uncommitted in your tree and the run's
  records are in espalier/.simple/{slug}/ (gitignored); read them, then
  delete the folder yourself`. The pipeline never reverts code and never
  deletes the folder on a non-Approve exit — what happened is in it.

### Completion (Approve only)

`- Status: COMPLETE` is written to the state file and the folder is deleted
in the same step — there is nothing to project and no trail to keep. The
run leaves exactly two things behind: the uncommitted change, and the
printed brief lines. `espalier-stats.sh` never sees a simple run; that is
the accepted cost of the mode.
