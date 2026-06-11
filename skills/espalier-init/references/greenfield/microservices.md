# Track: Microservices

**When:** multiple independently deployable services from day one. All
commands are **candidates — verify live before running.**

## 0. The gate question (ask FIRST, always)

> Microservices on day one is usually the wrong call — what constraint
> forces it? (separate teams owning separate domains · independent scaling
> profiles · polyglot requirement · regulatory isolation)

- **No concrete constraint named** → recommend a modular monolith
  (`backend.md` or `fullstack.md` with clean module boundaries — Espalier's
  layer rules enforce them) and record the exchange in
  `stack-decisions.md`. Only proceed here if the user insists.
- Constraint named → record it, proceed.

## 1. Grill question bank (≤ 3 rounds)

**Round MS1 — shape (grill decides, capped):**
- Which domains become services NOW? Derive candidates from the product
  brief, propose, let the user trim. **Hard cap: 3 services at init** —
  more domains become entries in a "later" list + the service template.
- Language(s): one language *(default — polyglot only if that was the
  forcing constraint)*. Per-language stack follows `backend.md` candidates.

**Round MS2 — communication:**
- **Edge:** gateway/BFF *(default — single public entry)* · direct
  per-service ingress.
- **Service-to-service:** REST + OpenAPI contracts *(default)* · gRPC
  (internal, perf) · async events (NATS *(default broker)* / Redis streams /
  Kafka only at real scale).
- **Contracts location:** `packages/contracts` (OpenAPI specs or proto
  files, generated clients) — single source of truth.

**Round MS3 — operations:**
- **Data:** db-per-service *(default — Postgres each, one compose)*;
  shared db is an anti-pattern, challenge it.
- **Deploy:** Fly.io per-service apps *(default)* · single VPS via compose ·
  k8s (only if the team already runs it — research live).
- CI provider (GitHub Actions default), observability floor: structured
  logs + request-id propagation across services (REQUIRED), tracing
  (OpenTelemetry) optional v1.

## 2. Stack candidates

Monorepo layout (pnpm workspaces / go workspace / uv workspace per
language):

```
services/<svc-a>/        # real domain service (from brief)
services/<svc-b>/        # second real domain service (if warranted)
services/_template/      # copyable service skeleton — how ALL future services start
gateway/                 # BFF/gateway (or provider-managed ingress)
packages/contracts/      # OpenAPI/proto + generated clients
docker-compose.yml       # full local env: services + dbs + broker
```

Per-service internals follow `backend.md` §2–§3 (framework, prod-grade
floor: healthz, structured logs, config validation, graceful shutdown).

## 3. Scaffold sequence

1. Workspace root + compose file (services, one Postgres per service,
   broker if MS2 chose events).
2. Scaffold service A fully (per `backend.md` sequence) → copy as
   `services/_template/` with placeholders → scaffold remaining service(s)
   FROM the template (proves the template works).
3. Gateway: thin route-proxy with auth at the edge.
4. Contracts package: spec per service + client generation script; services
   import generated clients, never hand-rolled fetch.
5. Request-id middleware in gateway + every service (propagate via header).
6. Root scripts: `dev` (compose up + all services), `test`, `lint`.

## 4. Deploy-ready config

- Dockerfile per service (+ gateway), root compose for local.
- CI: path-filtered per-service jobs (lint/test/build only what changed) +
  one all-up integration job (compose up, run cross-service smoke).
- Deploy: per-service deploy jobs gated on `main` + path filter
  (`fly deploy --config services/<svc>/fly.toml` or registry push).
- `docs/runbook.md`: adding a service from `_template` (checklist),
  contract-change workflow (spec → regen clients → consumers), per-service
  rollback, local debugging across services.

## 5. Test pyramid

| Layer | Scope |
|---|---|
| Unit | per service, no I/O |
| Integration | per service against its own real db |
| Contract | generated-client compatibility — consumer tests pinned to specs |
| Cross-service smoke | compose up everything; gateway → service A → service B happy path |

## 6. Release process

Independent per-service deploys (path-filtered). Contracts are versioned;
breaking a contract requires a deprecation window documented in the
runbook. No lockstep releases.

## 7. Verification commands

```bash
<install workspace>
<lint all> && <build/typecheck all>
docker compose up -d            # dbs (+ broker)
<migrate each service> && <test all>
# boot: compose up services; gateway healthz + one cross-service route
curl -fsS http://localhost:<gw-port>/healthz
curl -fsS http://localhost:<gw-port>/<route-touching-svc-a>
docker compose build            # every deploy artifact must build
```
