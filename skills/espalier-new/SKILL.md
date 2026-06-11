---
name: espalier-new
description: Start a brand-new project from an empty folder — adaptive interview, production-grade stack recommendation, scaffold with the ecosystem's own tools, deploy-ready config, verified build, then full Espalier setup. Use for "new project", "start from scratch", "scaffold an app", "greenfield", "/espalier-new"
---

# Espalier New — Greenfield Project Setup

Turn an empty folder into a production-ready project with an Espalier harness:
grill the user (product brief + stack), scaffold with the ecosystem's official
tooling, wire deploy/CI/test/release config, verify it builds and boots, offer
a guided first deploy, then converge into the standard `/espalier-init`
discovery pipeline.

## When to Use

- "/espalier-new"
- "Start a new project here"
- "Scaffold a new app / API / mobile app / CLI"
- "Set up a greenfield project with Espalier"

## Process

### 1. Bare check (gate)

This skill only operates on a **bare** folder. Run:

```bash
find . -path './.*' -prune -o -type f \( \
  -name package.json -o -name pyproject.toml -o -name setup.py -o -name go.mod \
  -o -name Cargo.toml -o -name pubspec.yaml -o -name Gemfile -o -name pom.xml \
  -o -name 'build.gradle*' -o -name '*.csproj' \
  -o -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' \
  -o -name '*.py' -o -name '*.go' -o -name '*.rs' -o -name '*.dart' \
  -o -name '*.swift' -o -name '*.kt' -o -name '*.java' -o -name '*.rb' \
  -o -name '*.cs' -o -name '*.php' -o -name '*.vue' -o -name '*.svelte' \
  \) -print 2>/dev/null | head -1
```

- **Empty output → bare.** README/LICENSE/.git/docs/editor config don't
  disqualify. Proceed to step 2.
- **Any output → NOT bare.** Stop and tell the user:

  > This repo already has code (`<first match>`). Scaffolding into a
  > non-empty repo is unsupported — most scaffolders refuse it, and Espalier
  > would overwrite nothing but learn the wrong thing. Run `/espalier-init`
  > instead to discover this codebase's conventions.

  Only continue if the user explicitly insists they understand and want a
  scaffold anyway.

- **`espalier/` already present** → this project is already set up; suggest
  `/espalier-init` (validate-only re-run) and stop.

### 2. Run the greenfield flow

Read and follow, in full:

```
${CLAUDE_SKILL_DIR}/../espalier-init/references/greenfield.md
```

That file owns everything from here: TTY precondition, adaptive grill
(product brief → track → track rounds), stack resolution, scaffold,
verification gate, guided-deploy offer, artifacts, and convergence into
espalier-init's Phase 0 → 1 → 2 → 3 (read
`${CLAUDE_SKILL_DIR}/../espalier-init/SKILL.md` when you reach convergence).

## Anti-Patterns

- Never scaffold without the user confirming the proposal first.
- Never run a scaffolder command from memory — verify current syntax live.
- Never write a real secret into any file (`.env.example` = placeholders).
- Never hand over a skeleton whose verification gate failed without saying so.
