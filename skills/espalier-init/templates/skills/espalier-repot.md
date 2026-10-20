---
name: espalier-repot
description: Move an existing Espalier install outside the project repo (espalier-main/<name>/, local git, nothing tracked) or back inside
---

# Espalier Repot

An espalier is sometimes moved to a new pot. This lane moves the `espalier/`
tree between the two places it can live:

- **inside** — `<project>/espalier/` is a real directory, tracked by the
  project repo; Stage 7 projects its records onto an espalier PR.
- **outside** — `<parent>/espalier-main/<name>/espalier/` holds the tree, in
  its own local git repo with no remote; the project holds a gitignored
  symlink `espalier` and NOTHING espalier-related is ever committed to it.
  Stage 7 commits records into that local repo; the code PR is the only PR.

`/espalier-init --outside` installs outside from the start. This lane is for a
project that already has an install and wants the other mode.

## When to Use
- "/espalier-repot" — move inside → outside (the default when the install is inside)
- "/espalier-repot --in" — bring an outside install back into the repo
- "Keep espalier out of this repo's git" / "stop committing espalier/"

## Flags

| Flag | Effect |
|------|--------|
| `--out` | Inside → outside. Default when `espalier/` is a real directory. |
| `--in` | Outside → inside. Default when `espalier` is a symlink into an outside root. |
| `--main=<dir>` | The espalier-main directory (default: the project's PARENT dir + `/espalier-main`). |
| `--name=<n>` | The folder under it (default: the project's basename — pass this when two projects share a basename). |

Parse the flags from the invocation; an unrecognized `--token` is a warning
and dropped. Nothing after the flags is read.

## Procedure

Every step runs from the project root. Nothing here commits in the project
repo — repot stages, the human commits.

### 1. Read the current mode

```bash
bash espalier/hooks/espalier-outside.sh status "$(git rev-parse --show-toplevel)"
```

`mode: inside` → the direction is `--out` unless `--in` was passed (then stop:
"already inside"). `mode: outside` → the direction is `--in` unless `--out`
was passed (then stop: "already outside — root: {root}"). `mode: none` → stop:
"no espalier install — run /espalier-init first".

### 2. Refuse while anything is in flight

The script refuses on its own (exit 6) when any
`espalier/changes/*/*/pipeline-state.md` has a non-terminal `- Status:` or an
espalier PR recorded but not merged. Run the move in step 4 and, on exit 6,
surface its list verbatim and stop — finish or abort those changes first
(`/espalier <requirement>` resumes each). Never move live state.

### 3. Confirm — ONE `AskUserQuestion`

Show the exact source and target before touching anything:

```
Repot espalier {out|in}:
  from: {current location}
  to:   {target location}
{--out:} The project repo will stop tracking espalier/, the .claude/ wiring,
         the CLAUDE.md section and the settings.json hooks — the removals are
         STAGED for you to commit. The tree keeps living at the target with
         its own local git (no remote; back it up yourself).
{--in:}  espalier/ becomes a tracked directory again; the wiring moves back to
         CLAUDE.md / settings.json / .gitignore and is STAGED. The outside root
         is left in place for you to delete once you are sure.
Options:
  1. Repot — do it
  2. Abort
```

Unattended runs (`interactivity_mode` returns `unattended`): stop with one
line — repot is a human act.

### 4. Move

```bash
R="$(git rev-parse --show-toplevel)"
# --out  (append --main=<dir> / --name=<n> when given)
bash espalier/hooks/espalier-outside.sh repot-out "$R"
# --in
bash espalier/hooks/espalier-outside.sh repot-in "$R"
```

`repot-out` moves the tree, writes `.espalier-origin` and the relative
symlink, initialises the local repo with a baseline commit
(`chore(espalier): repot from <project>`), untracks every espalier path the
repo carried (`git rm --cached`, staged), moves the hooks from
`.claude/settings.json` to `.claude/settings.local.json`, the `## Espalier`
section from `CLAUDE.md` to `CLAUDE.local.md`, drops the espalier lines from
`.gitignore` / `.gitattributes`, strips the dispatcher from a tracked
`.husky/post-merge`, writes the `.git/info/exclude` block, and records
`outside-root:` in `espalier/.espalier-config`.

`repot-in` is the inverse: copies the tree back into a real `espalier/`
directory, removes the symlink and the exclude block, moves the hooks and the
section back, restores the `.gitignore` / `.gitattributes` entries, drops the
config key, and stages the re-added paths. The outside root is NOT deleted.

Exit 3 = a collision (the target root belongs to another project, or already
holds a tree): surface the message and stop — `--name=<other>` is the usual
fix. Exit 6 = in flight (step 2).

### 5. Re-wire

The wiring files are rewritten for the new mode by the installed plugin's
bootstrap, in wire-only mode (it reuses the persisted merge decision):

```bash
# PLUGIN is the espalier-engineering checkout or plugin dir. Probe, in order:
#   $ESPALIER_PLUGIN_DIR · ~/.claude/plugins/espalier-engineering ·
#   ~/.claude/plugins/espalier · ~/repos/espalier-engineering
# (the same list bootstrap-espalier.sh itself probes); on Codex/Copilot, the
# clone the skill symlink points into (`pwd -P` through the link).
# --out:
bash "$PLUGIN/scripts/bootstrap-espalier.sh" --wire-only --outside --yes --plugin-dir="$PLUGIN/skills/espalier-init"
# --in:
bash "$PLUGIN/scripts/bootstrap-espalier.sh" --wire-only --yes --plugin-dir="$PLUGIN/skills/espalier-init"
```

Outside mode is also auto-detected from the symlink, so the `--outside` flag
on the `--out` re-wire is belt and braces. Validation runs at the end (same
check count; the gitignore / settings / CLAUDE.md checks read their outside
counterparts).

### 6. Report, never commit

Print `git status --short` (the staged removals or re-adds), the suggested
commit message the script printed (`chore: repot espalier outside the repo` /
`chore: repot espalier into the repo`), and — on `--out` — the outside root's
path with the reminder that its history lives only on this disk until a
remote is added by hand. Then stop: the commit is the human's.

## Platform notes

- **Claude Code** is fully covered: `CLAUDE.local.md` and
  `.claude/settings.local.json` are the local counterparts Claude Code loads
  beside the tracked files.
- **Codex / Copilot** have no local-only instruction file. On `--out`, a
  TRACKED `AGENTS.md`, `.github/copilot-instructions.md` or
  `.codex/config.toml` is left exactly as it is and bootstrap prints the
  section / hook block for a user-level file; the lines it already carries
  stay committed until you remove them by hand. Untracked ones are written
  and excluded locally.
- `repot-out` also untracks a tracked `.github/hooks/espalier-gates.json`,
  strips the `ESPALIER OWNERS v1` block from a tracked CODEOWNERS (removing
  the file when nothing else is in it), and strips the post-merge dispatcher
  from a tracked hook wherever bootstrap put it (`.husky/post-merge` or a
  `core.hooksPath` file) — every one of them staged, none committed. The
  re-wire reinstalls the dispatcher where git reads untracked hooks.
- The project remembers its outside root in its LOCAL git config
  (`git config --local espalier.outside-root`), never committed, so a
  non-default `--main` / `--name` root is found again after `git clean -fdx`
  removes the symlink: `espalier-outside.sh discover` (or any bootstrap run)
  relinks it.
- The outside root is per machine. Team mechanisms that ride the repo
  (CODEOWNERS routing, shared convention rows, the espalier PR) do not apply
  in outside mode — that is the trade the mode makes.
