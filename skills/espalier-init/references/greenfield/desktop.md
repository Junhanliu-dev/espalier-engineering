# Track: Desktop App (cross-platform)

**When:** primary interface is a desktop window. "Deploy" here is
**distribution**: installers, auto-update, signing. Signing/notarization
are config stubs + runbook — **never block init on certificates** (same
rule as mobile stores). All commands are **candidates — verify live
before running.**

## 1. Grill question bank (≤ 2 rounds)

**Round D1 — shell + frontend:**
- **Shell:** Tauri *(default — Rust core, small binaries, system webview,
  lower RAM)* · Electron (max ecosystem maturity, Node in main process,
  heavier) · other (Wails, Neutralino → BYO research).
  Decision drivers: team has Node-native needs in the main process →
  Electron; otherwise Tauri.
- **Inner frontend:** per `frontend.md` Round F1 (React default, Vite-based
  either way).

**Round D2 — distribution + needs:**
- **Target OSes:** all three *(default)* · subset.
- **Auto-update:** yes *(default)* — Tauri updater / electron-updater ·
  no (manual downloads).
- **Native needs** (from brief): filesystem heavy · tray/menubar ·
  notifications · local db (SQLite) — flag them; they shape
  permission/capability config (Tauri) or main-process modules (Electron).
- Deploy/distribution channel: GitHub Releases *(default)* · own site ·
  app stores (→ note extra signing requirements in runbook, out of init
  scope).

## 2. Stack candidates

| Candidate | Pick when |
|---|---|
| Tauri 2 + Vite/React + TS | default |
| Electron + electron-vite + TS + electron-builder | Node-in-main needed, team knows Electron |

Verify-live: `npm create tauri-app@latest` · electron-vite scaffold +
electron-builder config — both ecosystems move fast.

## 3. Scaffold sequence

1. Scaffolder (Tauri: create-tauri-app with chosen frontend; Electron:
   electron-vite template).
2. Frontend add-ons per `frontend.md` §3 (lint, prettier, vitest +
   Testing Library, Tailwind).
3. Shell side: Tauri — clippy+rustfmt on `src-tauri/`, capability/
   permission config minimal-by-default; Electron — main/preload/renderer
   separation, contextIsolation ON, nodeIntegration OFF (security
   defaults are non-negotiable).
4. E2E: Playwright (Electron has first-class support) · tauri-driver +
   WebDriver (verify current status live) — one smoke flow: app opens,
   main window renders.
5. Local persistence if flagged: SQLite via tauri-plugin-sql /
   better-sqlite3.
6. `.env.example` analogue: build-time config documented; runtime config
   in the app's config dir, never bundled secrets.

## 4. Deploy-ready (distribution) config

- **Packaging:** Tauri bundler / electron-builder — installer targets per
  chosen OS (dmg, msi/nsis, AppImage/deb).
- **CI matrix:** macOS + Windows + Linux runners; PRs build unpacked +
  test; tags build installers and attach to a GitHub Release + update
  manifest.
- **Auto-update:** updater config pointing at GitHub Releases; update
  signing keys as named TODO placeholders in CI secrets.
- **Code signing stubs:** macOS (Developer ID + notarization) and Windows
  (code-signing cert) config present but commented/TODO;
  `docs/runbook.md` covers obtaining certs, wiring secrets, and what
  unsigned builds mean for users (Gatekeeper/SmartScreen warnings) until
  then.

## 5. Test pyramid

| Layer | Tool |
|---|---|
| Unit/component | Vitest + Testing Library (renderer/frontend) |
| Shell logic | cargo test (Tauri commands) · vitest on main-process modules (Electron) |
| E2E smoke | Playwright / tauri-driver: launch, window renders, one IPC round-trip |

## 6. Release process

Version bump (tauri.conf.json / package.json — keep in sync via script) →
tag → CI matrix builds installers → GitHub Release + update manifest →
auto-updater picks it up. Rollback = re-point release tag / yank release
(documented in runbook).

## 7. Verification commands

```bash
<install>                          # npm + (Tauri: rust toolchain check)
<lint frontend> && <lint shell>    # eslint + (clippy | main-process lint)
<test>                             # vitest (+ cargo test for Tauri)
<dev-build boot>                   # tauri dev / electron-vite dev — window opens, then close
<package debug build>              # tauri build --debug / electron-builder --dir
# Packaging/signing stubs are LINT-CHECKED only (config parses);
# real signing is post-init (runbook), never part of the gate.
```
