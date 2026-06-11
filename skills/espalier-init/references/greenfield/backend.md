# Track: Pure Backend (API / service / worker)

**When:** no UI of its own — serves an API, processes jobs, or both.
Prod-grade here means more than lint: health endpoint, structured logging,
validated config, graceful shutdown, migrations. All scaffolder commands are
**candidates — verify live before running.**

## 1. Grill question bank (≤ 3 rounds)

**Round B1 — shape:**
- **API style:** REST + OpenAPI *(default)* · GraphQL · gRPC (internal
  service-to-service) · no API (pure worker/consumer).
- **Language:** TypeScript · Python · Go · Rust · other (→ BYO protocol).
  *Default: whatever the team knows; absent a team signal, TS.*

**Round B2 — persistence + work:**
- **Database:** Postgres *(default)* · SQLite (single-node, embedded) ·
  MongoDB (document-shaped domain) · none.
- **Background jobs:** none *(default)* · yes → pg-boss/BullMQ (TS) ·
  Celery/arq (Py) · River (Go) — prefer Postgres-backed queues until scale
  forces Redis.
- **Auth** (if brief said yes): JWT/session self-managed · hosted
  (Clerk/Auth0) · *default: track recommendation per framework.*

**Round B3 — operations:**
- **Deploy target:** Fly.io *(default — containers + Postgres nearby)* ·
  Railway · Docker/VPS · hyperscaler (AWS/GCP — research live).
- **CI provider:** GitHub Actions *(default)* · other (research live).

## 2. Stack candidates

| Lang | Framework | DB layer | Pick when |
|---|---|---|---|
| TS | Fastify | Drizzle + postgres-js | default TS — fast, minimal magic |
| TS | NestJS (`@nestjs/cli` → `nest new`) | Prisma | larger team wants DI structure |
| Python | FastAPI (via `uv init`) | SQLAlchemy 2 + Alembic | Python team / ML-adjacent *(Py default)* |
| Go | chi (or std `net/http`) | sqlc + pgx | ops-heavy, single static binary |
| Rust | axum | sqlx | extreme perf or Rust team |

Note: Fastify/FastAPI/chi have no one-shot full scaffolder — scaffold is
`init` + the **canonical layout from current official docs** (verify live;
don't invent structure).

## 3. Scaffold sequence

1. Init + canonical layout (`src/routes|api`, `src/services`, `src/db`,
   `src/config`, `tests/`).
2. Lint/format: ESLint+Prettier · Ruff (lint+format) · golangci-lint+gofmt ·
   clippy+rustfmt. Test: Vitest+supertest · pytest+httpx · `go test` ·
   `cargo test`.
3. Persistence: `docker-compose.yml` with Postgres (+ named volume), ORM
   wiring, **one real first migration** (not an empty stub).
4. Prod-grade floor (all of these, every backend):
   - `/healthz` endpoint (checks DB reachable).
   - Structured logging: pino · structlog · slog · tracing.
   - Config validation at boot: zod env schema · pydantic-settings ·
     envconfig — process refuses to start on missing config.
   - Graceful shutdown (SIGTERM → drain → close pool).
   - OpenAPI generation where the framework supports it.
5. `.env.example`: `DATABASE_URL`, `PORT`, `LOG_LEVEL` — names only.

## 4. Deploy-ready config

- Multi-stage Dockerfile (non-root user, prod deps only), `.dockerignore`.
- CI: lint → typecheck/build → test (against a Postgres service container)
  → `docker build` → deploy job gated on `main` (`fly deploy` /
  `railway up` / push to registry for VPS).
- Migrations run as a release step **before** new code takes traffic.
- `docs/runbook.md`: local dev (`compose up`), migration workflow, secrets
  (provider CLI — `fly secrets set` etc., never files), rollback
  (previous image + migration policy), log access.

## 5. Test pyramid

| Layer | Scope |
|---|---|
| Unit | services/pure logic, no I/O |
| Integration | routes against a REAL Postgres (CI service container or testcontainers) — not mocks |
| E2E smoke | boot the built artifact, hit `/healthz` + one real route |

## 6. Release process

Merge to `main` → deploy (default), or tag-triggered for deliberate cadence.
Migration always precedes traffic. Keep a `CHANGELOG.md` if consumers are
external.

## 7. Verification commands

```bash
<install>                       # npm ci / uv sync / go mod tidy / cargo fetch
<build or typecheck>            # tsc --noEmit / mypy opt / go build / cargo build
<lint>                          # eslint / ruff check / golangci-lint run / cargo clippy
docker compose up -d db && <migrate> && <test>
# boot: start server on ephemeral port, expect 200
<start> & curl -fsS http://localhost:$PORT/healthz && kill %1
docker build .                  # the deploy artifact must actually build
```
