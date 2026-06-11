# Track: Fullstack (web UI + own backend)

**When:** Web UI that needs its own server-side logic/data. Two shapes —
the shape question comes FIRST. All commands are **candidates — verify
live before running.**

## 1. Grill question bank (≤ 3 rounds)

**Round FS1 — shape (the big one):**
- **Single app** *(default for solo/small teams)*: Next.js — UI + API +
  server components in one deployable.
- **Monorepo split**: `apps/web` + `apps/api` + `packages/shared`
  (Turborepo + pnpm workspaces). Pick ONLY on a forcing constraint —
  separate backend team, non-TS backend, public API consumed by others,
  independent scaling. Ask for the constraint; none named → recommend
  single app and record the answer in `stack-decisions.md`.

**Round FS2 — data + auth:**
- **Database:** Postgres *(default)* · SQLite/libSQL (small) · hosted
  (Neon/Supabase Postgres).
- **ORM:** Drizzle *(default — SQL-first, light)* · Prisma (team prefers
  schema DSL).
- **Auth:** better-auth or Auth.js self-hosted *(default)* · Clerk (hosted,
  fastest) · none yet.

**Round FS3 — split-shape only:**
- **Contract:** tRPC *(default when both ends TS — end-to-end types)* ·
  OpenAPI + generated client (non-TS backend or public API).
- **API framework:** Hono *(default — light, edge-ready)* · Fastify.
- **Deploy:** web → Vercel, api → Fly.io *(default)* · both on one
  Docker/VPS host.

Single-app deploy: Vercel *(default)* · Fly/Docker (full control, no
vendor coupling). CI: GitHub Actions *(default)*.

## 2. Stack candidates

| Shape | Stack | Pick when |
|---|---|---|
| Single app | Next.js (App Router, TS) + Drizzle + Postgres + better-auth | default |
| Single app | Next.js + Prisma + hosted Postgres + Clerk | speed over control |
| Monorepo | Turborepo + pnpm: Next.js web · Hono api · tRPC · shared pkg | TS both ends, forcing constraint named |
| Monorepo | Turborepo: Vite SPA web · non-TS api (→ backend.md for that side) · OpenAPI contract | non-TS backend team |

Verify-live: `npx create-next-app@latest` · `npx create-turbo@latest`.

## 3. Scaffold sequence

**Single app:** create-next-app (TS, ESLint, Tailwind, App Router) →
Drizzle + compose dev Postgres + first migration → auth wiring →
Vitest + Testing Library → Playwright → `.env.example`
(`DATABASE_URL`, `AUTH_SECRET` placeholder names).

**Monorepo:** create-turbo → `apps/web`, `apps/api`, `packages/shared`
(types/schema), `packages/config` (shared tsconfig/eslint) → contract
layer (tRPC router in api, client in web; or OpenAPI gen) → per-workspace
lint/test → root scripts via turbo (`build`, `lint`, `test`, `dev`) with
affected-only caching. The api side inherits backend.md's prod-grade floor
(healthz, structured logs, config validation, graceful shutdown).

## 4. Deploy-ready config

- **Vercel (single app):** no Dockerfile needed; `vercel.json` only if
  defaults insufficient; CI deploy via Vercel integration or CLI gated on
  `main`; PR preview deploys native.
- **Fly/Docker:** multi-stage Dockerfile (Next standalone output / api
  image per app), compose for local.
- **Monorepo CI:** turbo-aware — build/test only affected workspaces;
  separate deploy jobs per app (web → Vercel, api → Fly), each gated on
  `main` + path filters.
- Migrations as release step before traffic (same rule as backend.md).
- `docs/runbook.md`: local dev, env promotion, secrets via provider CLI,
  rollback per provider.

## 5. Test pyramid

| Layer | Tool |
|---|---|
| Unit/component | Vitest + Testing Library |
| API/integration | route handlers / tRPC procedures against real Postgres |
| E2E | Playwright happy path against built app (web+api both up) |

## 6. Release process

Merge to `main` → deploy; PR previews for the web side. Tag releases
optional. Monorepo: deploys independent per app via path filters.

## 7. Verification commands

```bash
pnpm install            # or npm
pnpm build              # turbo build = all workspaces, affected-aware
pnpm lint && pnpm typecheck
docker compose up -d db && pnpm db:migrate && pnpm test
# boot: web (and api, if split) on ephemeral ports; expect 200
pnpm start & curl -fsS http://localhost:<port>/ && kill %1
# split shape: also curl api /healthz
```
