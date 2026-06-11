# Track: Mobile (iOS / Android)

**When:** primary interface is a phone app. Store distribution is this
track's "deploy" — config + stubs by default, guided store setup offered,
**never block init on certificates or store review.** All commands are
**candidates — verify live before running.**

## 1. Grill question bank (≤ 3 rounds)

**Round M1 — framework:**
- **Flutter** *(default — single codebase, mature tooling, consistent UI)*.
- **Expo (React Native)** — web/TS team, shared skills with web app, OTA
  updates via EAS Update.
- **Native (Swift/Kotlin)** — platform-specific needs; research live, treat
  as BYO.

**Round M2 — backend + state:**
- **Backend:** already exists (wire its URL) · need one too → run
  `backend.md` after this track · BaaS — Supabase *(default — Postgres,
  auth, realtime)* · Firebase (Google ecosystem).
- **State management:** Riverpod *(Flutter default)* · Bloc ·
  Zustand + TanStack Query *(Expo default)*.
- **Navigation:** go_router *(Flutter default)* · expo-router *(Expo default)*.

**Round M3 — distribution:**
- **Store launch planned now** → write fastlane/EAS stubs + runbook, offer
  guided store setup at the §7 point of greenfield.md.
- **Internal/testing first** *(default)* → debug + release artifact builds
  in CI; store stubs still written, credentials left as TODO.

## 2. Stack candidates

| Stack | Pick when |
|---|---|
| Flutter + Riverpod + go_router | default |
| Expo + TS + expo-router + Zustand/TanStack Query | TS/web team, OTA wanted |
| Native Swift/Kotlin | forcing platform constraint (→ BYO research) |

Verify-live: `flutter create` (use `--org com.<owner>`) ·
`npx create-expo-app@latest` (TS template).

## 3. Scaffold sequence

**Flutter:** `flutter create --org <org> .` → lints
(`flutter_lints`/`very_good_analysis`) → Riverpod + go_router → flavors
dev/staging/prod (Android productFlavors + iOS schemes; `--dart-define`
per-env config) → `flutter_test` + integration_test (or patrol) →
fastlane stubs per platform.

**Expo:** create-expo-app (TS) → ESLint+Prettier → expo-router → state
libs → `app.config.ts` with per-profile config → jest-expo + RN Testing
Library → maestro smoke flow stub → `eas.json` (dev/preview/production
build profiles) with credential fields as TODO.

Env/config: per-flavor config files or dart-define/EAS profile vars —
**no secrets in the repo**; runtime secrets come from the backend, build
secrets from CI secret store.

## 4. Deploy-ready (distribution) config

- **CI:** lint/analyze → test → build debug artifact on PRs; release
  artifacts (AAB/APK; iOS requires a macOS runner — note cost in runbook)
  on `main`/tags. Cache SDK/pub/npm layers.
- **Store stubs:** fastlane `Fastfile`+`Appfile` (Flutter) or EAS Build/
  Submit profiles (Expo), signing config referenced from CI secrets,
  every credential a named TODO placeholder.
- **OTA (Expo):** EAS Update wired into the release profile.
- **`docs/runbook.md`:** signing-key generation, store-listing checklist,
  TestFlight / Play internal-testing path, release + rollback (staged
  rollout percentages; OTA rollback for Expo).

## 5. Test pyramid

| Layer | Flutter | Expo |
|---|---|---|
| Unit | `flutter_test` | jest-expo |
| Widget/component | widget tests | RN Testing Library |
| Integration/E2E | integration_test or patrol | maestro flows |

CI runs unit + widget/component on every PR; integration on main or
nightly (emulator time is expensive).

## 6. Release process

Version bump (`pubspec.yaml` / `app.config.ts`) → tag → CI builds release
artifacts (+ EAS Update for OTA-eligible changes) → store submission via
fastlane/EAS once credentials exist (guided store setup fills them).
Staged rollout recommended in runbook.

## 7. Verification commands

```bash
# Flutter
flutter pub get
flutter analyze
flutter test
flutter build apk --debug          # boot proxy: build must succeed
# (running an emulator is NOT required for the gate — too heavy/flaky)

# Expo
npm install
npm run lint
npm test
npx expo export --platform android  # or npx expo prebuild --no-install
```

Gate = analyze/lint + tests + a debug build artifact. Emulator boot is
explicitly out of the gate (slow, flaky in CI containers); the runbook
covers manual first-run.
