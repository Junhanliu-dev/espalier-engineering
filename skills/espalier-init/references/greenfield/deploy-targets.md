# Guided First Deploy — Target Flows

**Read this when** the user accepted the guided-first-deploy offer
(greenfield.md §7). Goal: app live on a real URL before the session ends.

## Ground rules (every target)

- **User-driven, abortable.** Every step is announced before it runs;
  auth/login steps the user performs themselves (suggest `! <command>` so
  interactive CLI logins run in-session). Abort at any step loses nothing —
  the deploy-ready config stays for `docs/runbook.md` later.
- **Secrets (hard rule):** real values flow ONLY through the provider's
  CLI/secret store (`fly secrets set`, `vercel env add`, `wrangler secret
  put`, CI repo secrets). Never into any file, never echoed into the
  transcript when avoidable. `.env.example` keeps placeholder names.
- **CLI syntax drifts.** Confirm the current login/provision/deploy
  commands via find-docs/ctx7 before the first command of a flow.
- **Done =** deployed URL (or health endpoint) returns success, user sees
  it. Record target + URL + date in `stack-decisions.md` and the changes
  entry's `pipeline-state.md`.

## Choosing (when grill left it open)

| Target | Default for | Why |
|---|---|---|
| Vercel | frontend, fullstack single-app (Next.js), cms web side | zero-config Next, preview deploys |
| Fly.io | backend, fullstack api side, microservices | containers + managed Postgres near app |
| Railway | backend when user wants dashboard-first UX | simplest db+service pairing |
| Cloudflare | static frontend, edge workers | free tier, global edge |
| Docker/VPS | user owns a server / no-vendor constraint | full control, no lock-in |
| anything else | user named it | research-per-run (below) |

## Vercel (frontend / Next.js / cms-web)

1. `vercel login` (user runs) → 2. `vercel link` (create project) →
3. env vars: `vercel env add <NAME>` per `.env.example` entry that has a
   real value (db URL from the db provider, auth secret generated now) →
4. `vercel deploy --prod` → 5. verify: open the URL, expect 200.
Postgres for fullstack: provision via the user's chosen db host (Neon /
Vercel-integrated storage — confirm current offering live), then step 3.

## Fly.io (backend / api / services)

1. `fly auth login` → 2. `fly launch --no-deploy` (generates/adopts
   `fly.toml`; review it — keep our Dockerfile) → 3. Postgres: `fly
   postgres create` + `fly postgres attach` (sets `DATABASE_URL` secret) →
4. other secrets: `fly secrets set NAME=value` → 5. release command =
   migration (wire in `fly.toml`) → 6. `fly deploy` → 7. verify:
   `curl https://<app>.fly.dev/healthz`.
Microservices: repeat per service (own `fly.toml` each); gateway last.

## Railway (backend + db, dashboard-first)

1. `railway login` → 2. `railway init` → 3. add Postgres plugin (CLI or
   dashboard; sets `DATABASE_URL`) → 4. `railway variables set` for the
   rest → 5. `railway up` → 6. generate domain, verify healthz.

## Cloudflare (static / Workers)

1. `wrangler login` → 2. Pages: `wrangler pages project create` +
   `wrangler pages deploy <dist>` · Workers: `wrangler deploy` →
3. secrets: `wrangler secret put` (Workers only) → 4. verify the
   `*.pages.dev` / `*.workers.dev` URL.

## Docker / VPS (generic)

No provider account assumed. Guided flow proves the artifact, not the
host:

1. `docker build -t <app> .` → 2. `docker run` locally with env from a
   NON-committed local env file → 3. verify localhost healthz →
4. if the user has a registry + server NOW: push, then SSH deploy per
   runbook (compose pull + up) → verify server URL. Otherwise stop here —
   the runbook documents the server half.

## Mobile / desktop analogue

These tracks have no URL. Their guided offer is **guided store setup**
(mobile) / **guided signing setup** (desktop) — follow the track file's
runbook section interactively as far as the user's accounts allow. Stubs
are already written either way; partial progress is normal (cert
generation takes days at Apple's pace).

## Research-per-run (uncurated target)

User named a target not listed (Render, Deno Deploy, AWS, k8s cluster,
…):

1. Oracle: current official CLI flow for "deploy <track's artifact
   shape> to <target>" — login, provision, secrets, deploy, verify steps.
2. Sanity-check the plan against the ground rules above (especially
   secrets handling), present it, then walk it step-by-step like any
   curated flow.
3. Record the researched flow in `docs/runbook.md` so the next deploy
   doesn't need research.

## After a successful deploy

- CI deploy job: confirm the workflow's deploy step matches what was just
  done manually (same command family, secrets from CI secret store; add
  the provider token to repo secrets — name it, point user at where).
- Note URL + provider + rollback command in `docs/runbook.md`.
- Update `stack-decisions.md` + changes entry as per ground rules.
