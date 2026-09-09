# context-report (seed for `scripts/context-report.py`, plan Track F.2)

These four scripts are the seed: one-off passes written for the 2026-09-08 portal
mining, `ROOT` hardcoded, findings in `docs/context-field-report-2026-09-08.md`. The
consolidated tool is `scripts/context-report.py` (any project dir, `--since/--until`,
`--repo`, `--json`, `--bare`; documented in `docs/usage-cost.md`) — run that one. The
seeds stay as the record of how each number was first derived.

Mines a Claude Code project directory (`~/.claude/projects/<slug>/`) for where
each espalier agent's tokens actually go: first-turn / peak / calls / total per
spawn by agent type, residency-weighted read categories, spawn-length tail,
pack cohort, orchestrator sessions, on-demand disclosure rates.

Run in order (all read-only; each takes a few seconds):

```bash
python3 mine_transcripts.py   # per-type spend map, most-read files, main sessions; writes subagents.json
python3 mine2.py              # residency-weighted categories, tail analysis, orchestrator composition
python3 mine3.py              # accounting closure (baseline / tool results / own output), version + model by week
python3 mine4.py              # task-notification sizes, quality-proxy join, spawn labels (needs subagents.json)
```

`ROOT` at the top of each script points at the portal project; change it for
another install. Findings from the 2026-09-08 run: `docs/context-field-report-2026-09-08.md`
and `docs/quality-first-context-plan.md` §0.
