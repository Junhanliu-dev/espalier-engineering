# Track: Pure Frontend (SPA / static site)

**When:** Web UI whose backend exists elsewhere (or isn't needed). Own
backend wanted → `fullstack.md`. Content site with CMS editors → `cms.md`.

All commands below are **candidates — verify current syntax live (§4 of
greenfield.md) before running.**

## 1. Grill question bank (≤ 2 rounds here)

**Round F1 — shape** (skip anything the brief already answered):
- **Site nature:** app-like (dashboard, interactive tool) → SPA · content-heavy
  (marketing, blog, docs) → Astro. *Default: app-like.*
- **Framework:** React *(default — largest ecosystem/hiring pool)* · Vue ·
  Svelte · no preference (→ React).
- **Styling:** Tailwind *(default)* + shadcn/ui (React only) · component
  library · plain CSS.

**Round F2 — surroundings:**
- **Backend API:** URL/contract exists? → wire `VITE_API_URL` + MSW mocks ·
  none → skip MSW.
- **E2E depth:** Playwright smoke (happy path) *(default)* · full e2e suite ·
  none (unit/component only).
- **Storybook:** no *(default for solo)* · yes (team / design-system work).
- **Deploy target:** Cloudflare Pages *(default — generous free tier)* ·
  Vercel · Netlify · Docker/VPS (nginx).
- **CI provider:** GitHub Actions *(default)* · other (research live).

## 2. Stack candidates

| Candidate | Pick when |
|---|---|
| Vite + React + TS | default for app-like UIs |
| Vite + Vue + TS | team knows Vue |
| Vite + Svelte + TS | bundle-size / perf sensitive |
| Astro + TS (islands as needed) | content-heavy; ships ~zero JS by default |

Verify-live targets: `npm create vite@latest` · `npm create astro@latest`.

## 3. Scaffold sequence

1. Scaffolder (TS variant) into `.` — if it refuses a non-empty dir, scaffold
   to temp and move contents in, preserving `.git`.
2. Add-ons: ESLint (flat config) + Prettier, Vitest + Testing Library +
   jsdom, Playwright (`npx playwright install --with-deps chromium` in CI),
   Tailwind (+ shadcn/ui if chosen), MSW if mocking.
3. Structure: `src/components/`, `src/lib/`, route layer if a router is used.
4. `.env.example`: `VITE_API_URL=` etc. — names only, no values.
5. `package.json` scripts: `dev` · `build` · `preview` · `lint` ·
   `typecheck` (`tsc --noEmit`) · `test` · `test:e2e`.

## 4. Deploy-ready config

- **CDN targets (default):** no Dockerfile — deploy = build output upload.
  CI deploy job uses the provider's action/CLI (wrangler / vercel / netlify),
  gated on `main`. PR preview deploys via provider's native support.
- **Docker/VPS target:** multi-stage Dockerfile (build → nginx serving
  `dist/`, non-root), `.dockerignore`.
- **CI** (`.github/workflows/ci.yml`): install (with cache) → lint →
  typecheck → test → build → e2e (chromium) → deploy job (main only).
- **`docs/runbook.md`:** environments, preview-deploy flow, env vars
  (provider dashboard, never committed), rollback = provider's previous-
  deployment promote.

## 5. Test pyramid

| Layer | Tool | Scope |
|---|---|---|
| Unit/component | Vitest + Testing Library | components, lib functions |
| API boundary | MSW | mock server responses in tests |
| E2E | Playwright | happy-path smoke (default), chromium-only in CI |
| Visual (opt-in) | Storybook | when chosen in F2 |

## 6. Release process

Continuous: merge to `main` → production deploy; PRs → preview URLs.
Optional conventional-commit CHANGELOG. No version ceremony — it's a site.

## 7. Verification commands

```bash
npm install
npm run build
npm run lint && npm run typecheck
npm test -- --run
# boot: preview the real build on an ephemeral port, expect HTTP 200
npm run preview -- --port 0 &   # capture the printed port
curl -fsS http://localhost:<port>/ >/dev/null && kill %1
```
