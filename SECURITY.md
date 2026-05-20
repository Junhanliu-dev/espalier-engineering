# Security Policy

## Supported Versions

Only the latest minor version receives fixes. Older versions are not patched.

| Version | Supported |
|---------|-----------|
| 0.5.x   | ✓         |
| 0.4.x   | use `/espalier-migrate` to upgrade |
| 0.3.x   | use `/espalier-migrate` to upgrade |
| 0.2.x   | use `/espalier-migrate` to upgrade |
| 0.1.x   | use `/espalier-migrate` to upgrade |

## Reporting a Vulnerability

If you find a security issue in Espalier Engineering, please report it privately rather than opening a public issue.

**Preferred channel:** [GitHub private vulnerability reporting](https://github.com/Junhanliu-dev/espalier-engineering/security/advisories/new) — opens a private security advisory the maintainer can triage.

**Fallback:** email the maintainer (address listed in `.claude-plugin/plugin.json` author field).

Please include:
- Affected version(s)
- Reproduction steps
- Impact assessment (what the attacker can achieve)
- Suggested fix if you have one

## What counts as a vulnerability

Espalier Engineering is a Claude Code plugin that:
1. Reads source files in the target project (Phase 1 discovery scouts).
2. Writes files into the target project (Phase 2 substitution writes, Phase 3 bootstrap).
3. Symlinks `.claude/{rules,skills,agents}` into the target project.
4. Modifies `.claude/settings.json` to register hooks.
5. Optionally installs a `.git/hooks/post-merge` hook.

In-scope vulnerabilities include:
- Path traversal in scout file reads or bootstrap script writes.
- Arbitrary command execution via crafted target-project contents (e.g., malicious filename triggers shell injection in a hook).
- Privilege escalation via the post-merge hook install (e.g., hook content injection).
- Symlink attacks during `safe_ln` (the wrapper specifically refuses to clobber regular files — bypasses are in scope).
- Skill-loader confusion (e.g., crafted SKILL.md that breaks Claude Code skill discovery).

Out of scope:
- The user running `/espalier-init` on a malicious target project they don't control — that's an "untrusted code" problem, not an Espalier issue.
- Bugs in the discovery scouts producing inaccurate output (file an issue, not a security report).
- Issues in Claude Code itself, the Anthropic SDK, or any other dependency — report to those projects directly.

## Response timeline

- Acknowledgement: within 7 days.
- Initial assessment: within 14 days.
- Fix + release: depends on severity. Critical issues prioritized; lower-severity issues may roll into the next planned release.

## Coordinated disclosure

Once a fix lands and a patched release ships, the maintainer will publish a GitHub security advisory crediting the reporter (unless anonymity is requested).
