# Multi-Dev Maintenance — How It Works (Plain Language)

**Audience:** anyone on a team (roughly 2–10 developers) whose repo uses espalier. No espalier internals required.
**Spec:** `docs/multi-dev-maintenance-implementation-plan.md` (revision 5). Where this doc and the plan disagree, the plan wins.

---

## What espalier keeps, and why it goes stale

Espalier extracts a knowledge base from your codebase and stores it in the repo under `espalier/`: coding rules, a wiki describing the architecture, skills for AI coding agents, and an audit trail of changes. That knowledge describes the code — so every time the code changes, some of it can silently become wrong.

Espalier already handles this for a single developer:

- A git hook watches your pulls and quietly flags docs that look stale (the flags live in a private file on your machine, never committed).
- A periodic check-up command, `/espalier-doctor`, re-scans for drift on a schedule (say, weekly).
- A refresh command, `/espalier-prune`, regenerates a stale doc and asks you to approve the result. Nothing is ever rewritten silently.
- When your code reviews keep noticing the same new pattern (say, three separate changes all return `Result<T,E>` where the rule says otherwise), espalier asks: should this become the new rule? That's called **promotion**.

## What breaks with ten developers

Four things, all variations of "the loop was designed for one person":

1. **Everyone sees a different staleness picture.** The drift flags are per-machine, so your clone and mine disagree about what's stale.
2. **Nobody owns the check-up.** The weekly doctor reminder fires for all ten of us. Each of us assumes someone else ran it. Nobody does. (Or all ten of us do, redundantly.)
3. **The shared bookkeeping files collide.** Convention observations from different branches append to the same file, and git has no idea how to merge them.
4. **Rules fork.** If my branch promotes a new convention, your branch keeps enforcing the old rule until my PR merges — and if we both promote different things, the rule canon quietly splits.

## The model: one gardener, small files, git does the rest

The design has three moving parts. None of them add clever machinery — they mostly *remove* opportunities for collision.

### 1. The weekly gardener

Maintenance stops being everyone's job-in-theory and becomes **one person's 15-minute job per week, rotating**.

The gardener's loop:

1. Espalier opens a temporary worktree of the main branch for you — your own feature branch and working directory are never touched.
2. Run `/espalier-doctor` — the scan.
3. Run `/espalier-prune` over whatever the scan flagged — approve or reject each regenerated doc.
4. If the prune fixed everything the scan found, run the doctor once more (it's fast on a clean tree) so the recorded stamp says **clean** — otherwise the team-wide reminder would keep firing about findings you already fixed.
5. Push one maintenance PR: `docs: weekly espalier maintenance`. It contains the scan stamp and the doc refreshes, nothing else.

That's it. One scan per team per week instead of ten. One prune sweep instead of ad-hoc pruning from ten different branches. And because the result is a PR, the usual review flow applies — if any rule file changed, GitHub automatically asks the rule owner to review (see "Roles" below); the routine parts just need any teammate's quick approval when the repo requires PR reviews.

Everyone else's experience: when you start a pipeline run, espalier's pre-flight might mention "2 stale docs, doctor due" — and the default answer is now simply **Proceed**, because the weekly maintenance handles it. Nine out of ten people never think about maintenance at all.

**What if the gardener skips a week?** Nothing dramatic. The shared stamp ages out, and the old behavior returns automatically: the reminder starts nagging everyone again until someone runs the scan. The rota is a convenience, not a single point of failure.

### 2. Two small shared files instead of merge machinery

Two facts need to be visible to the whole team through git:

**"When was the last check-up, and was it clean?"** — a one-line tracked file, `espalier/.doctor-stamp`, written only by the doctor as part of the maintenance PR. It records the time and either `clean` or `dirty: 3` (three findings). An honest subtlety: only a **clean** scan counts as "the team is covered". A dirty scan tells everyone drift exists, but it never silently means "handled" while the findings sit on one person's machine.

**"What convention observations and decisions exist?"** — one tiny file per pattern, under `espalier/conventions/`. Each file holds the observations for one convention and its current status. This is the same trick changelog tools like towncrier use: many small files can't conflict with each other. Two branches recording observations about *different* patterns touch *different* files — git merges them without ever asking a human. That covers almost all real concurrency on a ten-person team.

### 3. Conflicts that are rare, small, and meaningful

The old design goal was "conflicts must be impossible", which required event logs, merge folds, and format versioning. The shipped design accepts a weaker, cheaper goal: **conflicts are rare, and when they happen they're tiny and they mean something**.

- Two people promote the *same* convention differently on two branches? Git shows a conflict in one five-line file. That conflict **is** the alarm — two people made contradictory rule decisions, and a human (the rule owner) should look. The tooling couldn't have decided that for you anyway.
- Two branches both recorded an observation about the *same* pattern in the same window? A two-line conflict in that pattern's file. Keep both lines. Thirty seconds.
- Two doctors ran in the same week (a rota mix-up)? The stamp file conflicts: one line versus one line. Keep the newer one. Done.
- Two branches both regenerated the same wiki page? Don't hand-merge regenerated prose. Take either side, finish the merge, and re-run `/espalier-prune` on that file — regeneration over the merged code *is* the merge.

## Where each kind of maintenance happens

| Activity | Where | Why |
|---|---|---|
| Doctor (check-up scan) | Weekly maintenance PR only | The shared stamp is the whole point — it must land where everyone sees it. |
| Prune (doc refresh) | Weekly maintenance PR, normally | One sweep per week means two people basically never regenerate the same doc on different branches. |
| Prune escape hatch | Your feature branch, if a doc *you* need is critically stale | As its own isolated `docs:` commit. Worst case is a conflict covered by the recipe above. |
| Convention observations | Your feature branch, automatically | Written during your normal pipeline runs; per-pattern files make them merge-safe. |
| Promotion (rule changes) | Your feature branch | You have the context; your PR gets routed to the rule owner for review regardless of which branch it came from. |

## Roles

- **Everyone:** work normally. Say "Proceed" at the pre-flight. Your pulls quietly update your local drift flags; your reviews quietly record convention observations.
- **The week's gardener (rotating):** the 15-minute loop above.
- **The rule owner:** named in the generated CODEOWNERS file. Reviews any PR that touches `espalier/rules/` — promotions and rule refreshes, a few per month. Sanity-checks that a promoted pattern is real team consensus and doesn't contradict an existing rule. **Important:** CODEOWNERS only enforces anything if the repo enables branch protection with "Require review from Code Owners". Without that setting it's advisory. At ten developers, turn it on.

## Honest limitations

- **Local drift flags stay local.** Your machine's staleness picture and mine still differ between maintenance runs. The weekly scan is the equalizer. (A fully-shared drift state design exists on the shelf in the plan, to be built only if this actually hurts.)
- **A refresh from the escape hatch describes your branch's tree**, including your unmerged code. It becomes accurate when your PR merges; if the PR is abandoned, the flag simply resurfaces and the next prune fixes it.
- **Teammates who never ran espalier's setup** have no local drift detection, but they inherit everything tracked: the rules, the wiki, the stamp, the convention files. The weekly doctor is their safety net too.
- **The rota is social.** Espalier documents it and defaults everyone's prompts around it, but it can't force a human to take their turn — it can only fall back to nagging everyone when the stamp goes stale.
