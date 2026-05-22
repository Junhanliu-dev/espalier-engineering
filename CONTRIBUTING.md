# Contributing to Espalier Engineering

Thanks for the interest. This doc tells you how the project is laid out, what kinds of contributions are welcome, and how to land a change cleanly.

## Project layout

```
.claude-plugin/          # plugin manifests (plugin.json, marketplace.json)
scripts/                 # bootstrap-espalier.sh, migrate-v0.1-to-v0.2.sh, migrate-v0.3-to-v0.4.sh, migrate-v0.4-to-v0.5.sh, test-bootstrap.sh
skills/
├── espalier-init/       # the main /espalier-init skill (Phase 0-3 orchestrator)
│   ├── SKILL.md         # phase index — entrypoint
│   ├── templates/       # markdown templates emitted into target projects
│   ├── hook-templates/  # shell hooks emitted into target projects
│   └── references/      # deep-dive content (discovery checklist, wiring, validation)
└── espalier-migrate/    # /espalier-migrate skill (auto-detect + dispatch migrations)
docs/                    # migration guides + design plans
CHANGELOG.md             # release notes
README.md                # value prop + install + usage cost
```

## Local dev setup

```bash
git clone git@github.com:Junhanliu-dev/espalier-engineering.git ~/repos/espalier-engineering
cd ~/repos/espalier-engineering

# Sideload the skill into Claude Code for testing
ln -sfn ~/repos/espalier-engineering/skills/espalier-init    ~/.claude/skills/espalier-init
ln -sfn ~/repos/espalier-engineering/skills/espalier-migrate ~/.claude/skills/espalier-migrate
export ESPALIER_PLUGIN_DIR=~/repos/espalier-engineering/skills/espalier-init

# Restart Claude Code so skills are picked up
```

## Running tests

```bash
# Bootstrap smoke suite — 43 assertions covering all phases of bootstrap-espalier.sh
bash scripts/test-bootstrap.sh --verbose
```

For the migration scripts, the test harness is described in `docs/migrating-v0.3-to-v0.4.md` (synthetic v0.3 fixture + dry-run + apply).

Before opening a PR, scripts must parse clean under macOS system bash 3.2.57:

```bash
for f in scripts/*.sh skills/espalier-init/hook-templates/*.sh; do
  /bin/bash -n "$f" || echo "BAD: $f"
done
```

## Types of contributions

| Type | Where it goes | Notes |
|---|---|---|
| Bug fix in bootstrap / migration scripts | `scripts/` | Must pass `test-bootstrap.sh` + bash 3.2 syntax check |
| New child skill template | `skills/espalier-init/templates/skills/` | Add to bootstrap's Stage 3 cp list; SKILL.md `name:` must equal folder name |
| New hook template | `skills/espalier-init/hook-templates/` | Add to bootstrap's Stage 4 cp list; chmod-glob picks it up |
| Discovery scout addition (Phase 1) | `skills/espalier-init/references/discovery-checklist.md` | Add to "Parallel Execution Recipe" + update SKILL.md Phase 1 |
| Validation check | `scripts/bootstrap-espalier.sh` Stage 11 | Bump the `/28` total in `run_check`; add the check; add a row to `references/validation.md` |
| Docs / typos / examples | `README.md`, `docs/`, in-file comments | No tests needed |
| New migration (e.g. v0.5 → v0.6) | `scripts/migrate-v0.5-to-v0.6.sh` + update `/espalier-migrate` detection | Follow an existing `migrate-v*.sh` as template |

## Cross-platform requirements

Shell scripts in this repo MUST work on:
- macOS system bash (3.2.57) — no `declare -A`, no `mapfile`, no `${var^^}`
- BSD sed (macOS default) — no `(^|...)` alternation anchors in `-E` mode
- BSD `stat` and GNU `stat` (use `uname` check to branch arg format)

The migration script's `_rewrite_file()` is the reference pattern for portable sed.

## Pull request checklist

- [ ] Branch named `feat/<short-desc>` or `fix/<short-desc>` or `docs/<short-desc>`
- [ ] `scripts/test-bootstrap.sh --verbose` passes 43/43
- [ ] All shell scripts pass `bash -n` under `/bin/bash` (macOS 3.2.57)
- [ ] If changing migration scripts, dry-run + apply tested against synthetic v0.3 fixture under both `/bin/bash` and homebrew bash
- [ ] CHANGELOG.md updated under the next version heading
- [ ] If breaking change: noted in CHANGELOG breaking-changes table + migration script provided

## Commit message style

Imperative mood, short subject line (~50 chars), wrap body at 72:

```
fix: handle missing pre-push-gate-wrapper template

v0.2.x .claude/settings.json referenced a wrapper file that was never
shipped as a template. Bootstrap now copies the wrapper from
hook-templates/ and Stage 11 validation checks it's executable.
```

Co-author trailers and Claude attribution NOT required and NOT preferred.

## Reporting bugs

Open an issue using the **Bug report** template. Include:
- Plugin version (from `/plugin list` or `.claude-plugin/plugin.json`)
- OS + shell (`uname -a` + `/bin/bash --version`)
- Reproduction steps
- Full error output (un-redacted hook + script stderr if possible)

## Requesting features

Open an issue using the **Feature request** template. The maintainer prioritizes based on:
- How many users would benefit
- Whether it preserves the "one-time init tax → reuse forever" model
- Whether it can be encoded as machine-enforceable constraint (vs. prompt advice)

## Releases

Versioning: SemVer. `MAJOR.MINOR.PATCH`.

- MAJOR: breaking change to skill names, slash commands, or target-project dir layout.
- MINOR: new feature, additive change to bootstrap stages, new skill.
- PATCH: bug fix only, no surface change.

Release process: see `CHANGELOG.md` for the v0.4.x pattern (single commit, signed tag, gh release with notes).

## License

MIT — by submitting a contribution, you agree it's licensed under the same terms as the rest of the repo.
