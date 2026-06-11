# Track: CLI Tool / Library (SDK / package)

**When:** no service, no UI — a tool humans run, or a package other code
imports. The "deploy" here is **publishing** (registry) or **distributing**
(binaries). All commands are **candidates — verify live before running.**

## 1. Grill question bank (≤ 2 rounds)

**Round CL1 — kind + language:**
- **Kind:** CLI tool · library/SDK · both (CLI that's also importable —
  common; structure as library with a thin CLI entry).
- **Language:** Go *(CLI default — single static binary, easy distribution)* ·
  Rust (perf, same distribution story) · Python *(default when the audience
  is Python devs)* · TypeScript *(default when the audience is JS devs)*.
  Pick by AUDIENCE, not preference — a JS-ecosystem dev tool in Go costs
  you contributors.

**Round CL2 — distribution:**
- **CLI:** GitHub Releases binaries *(Go/Rust default — goreleaser /
  cargo-dist)* · npm (TS) · PyPI via uv/pipx (Python) · Homebrew tap
  (offer as stub).
- **Library:** npm *(TS)* · PyPI *(Py)* · crates.io *(Rust)* · Go module
  (just tags).
- **Versioning:** semver via changesets (TS) / release-please or
  tag-driven (Go/Py/Rust) *(defaults)*.

## 2. Stack candidates

| Kind | Lang | Stack |
|---|---|---|
| CLI | Go | `go mod init` + cobra (or std `flag` for tiny tools) + goreleaser |
| CLI | Rust | `cargo new` + clap (derive) + cargo-dist |
| CLI | Python | `uv init --package` + typer + PyPI (pipx-installable) |
| CLI | TS | `npm init` + citty/commander + tsup + npm bin |
| Library | TS | tsup (ESM+CJS dual) + vitest + changesets + npm |
| Library | Python | `uv init --lib` + pytest + uv build/publish |
| Library | Rust | `cargo new --lib` + cargo publish |
| Library | Go | `go mod init` + tags (no registry step) |

Verify-live: goreleaser config schema, cargo-dist init, changesets setup,
uv publish flow — all of these move.

## 3. Scaffold sequence

1. Init per table → canonical layout (`cmd/` + `internal/` for Go;
   `src/` + thin `bin` entry for TS; package dir + `cli.py` for Python).
2. Lint/format/test per language (`backend.md` §3 list).
3. **CLI extras:** `--help` golden test, `--version` wired to build-time
   version injection, exit-code conventions documented.
4. **Library extras:** public-API surface in one entry module; TS: dual
   ESM/CJS build via tsup + `exports` map + type declarations checked
   (attw/publint as candidates — verify live).
5. README with install + 30-second usage (the README IS the product page
   for this track), LICENSE check, `CHANGELOG.md`.

## 4. Deploy-ready (publish) config

- **CI (PRs):** lint → typecheck/build → test, on a small OS/runtime matrix
  (libraries: test the runtimes you claim to support).
- **Release workflow (tags / changesets-merge):**
  - Go/Rust CLI: goreleaser / cargo-dist → GitHub Release with binaries +
    checksums; Homebrew tap stub (TODO).
  - TS: changesets version PR → merge → `npm publish --provenance`.
  - Python: build → publish to PyPI (trusted publishing / OIDC preferred
    over tokens — verify current setup live).
  - Registry credentials live in CI secrets — named TODO placeholders +
    runbook steps, never committed.
- `docs/runbook.md`: first-publish checklist (name availability, org
  scope, trusted-publisher registration), yanking/deprecation policy.

## 5. Test pyramid

| Layer | Scope |
|---|---|
| Unit | core logic |
| CLI-level | run the built binary: `--help`, `--version`, one real command, exit codes |
| Library-level | import-and-use test against the BUILT artifact (catches packaging breaks, not just source breaks) |

## 6. Release process

Tag (or changesets merge) → CI builds + publishes → GitHub Release notes
from CHANGELOG. Semver discipline documented: breaking = major,
no exceptions. First release is `0.1.0`, not `1.0.0`.

## 7. Verification commands

```bash
<install> && <lint> && <build>
<test>
# CLI boot: the BUILT artifact runs
<built-binary> --help && <built-binary> --version
# Library boot: packaging works, not just source
<pack + install into tmp env + import>   # npm pack / uv build / cargo package --list
```
