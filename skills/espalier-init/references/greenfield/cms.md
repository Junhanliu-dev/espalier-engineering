# Track: Next.js + Headless CMS

**When:** content-heavy web product where non-developers edit content
(marketing site, blog network, brochure+app hybrid). Pure docs/blog with
dev-only authors → `frontend.md` (Astro + markdown) is usually enough —
say so before committing to a CMS. All commands are **candidates — verify
live before running.**

## 1. Grill question bank (≤ 3 rounds)

**Round C1 — editors + hosting:**
- **Who edits content?** developers only → challenge the CMS need (Astro +
  git-based content may suffice; record the answer) · non-technical
  editors → CMS confirmed.
- **CMS hosting:** self-hosted *(default — Payload inside Next.js, one
  deployable, no per-seat fees)* · hosted SaaS (Sanity — zero ops, real-time
  collab) · self-hosted separate service (Strapi/Directus — CMS as own API).

**Round C2 — content + frontend:**
- **Content model seeds** (from product brief): pages, posts, authors,
  media — list the obvious types, confirm. Keep v1 minimal; editors evolve
  it.
- **Rendering:** static-first with revalidation *(default — ISR)* · fully
  dynamic (personalized content).
- **Preview:** editors need draft preview? *(default: yes)* → wire
  Next.js Draft Mode + CMS preview hooks.

**Round C3 — operations:** deploy target (Vercel + CMS co-location per C1
choice), CI provider, e2e depth — same defaults as `fullstack.md`.

## 2. Stack candidates

| Candidate | Pick when |
|---|---|
| Next.js + Payload (embedded, same repo/deploy) + Postgres | default — TS-native, one deploy unit |
| Next.js + Sanity (hosted) | zero CMS ops, collaborative editing |
| Next.js + Strapi (separate self-hosted service) | CMS API reused by other apps |
| Next.js + Directus (separate, DB-first) | CMS over an existing/SQL-shaped schema |

Verify-live: `npx create-payload-app@latest` · `npm create sanity@latest` ·
`npx create-strapi-app@latest` — Payload's Next.js-embedded install
especially (its setup moved between major versions).

## 3. Scaffold sequence

1. **Payload (default):** create-payload-app with the Next.js template (or
   add to a create-next-app per current docs) → Postgres via compose +
   first migration → define seed collections from C2 (pages, media,
   globals/nav) → seed script with sample content.
2. **Hosted/separate CMS:** create-next-app first (per `fullstack.md`
   single-app sequence) → CMS project/scaffold → typed client (Sanity
   GROQ/typegen; Strapi/Directus REST/GraphQL client) in `src/lib/cms/`.
3. Draft preview wiring (Next Draft Mode ↔ CMS preview URL) when C2 said
   yes.
4. Standard add-ons: ESLint+Prettier, Vitest, Playwright, Tailwind,
   `.env.example` (CMS URL/tokens as placeholder NAMES).

## 4. Deploy-ready config

- **Embedded Payload:** one deploy (Vercel or Fly/Docker); Postgres
  attached; migrations as release step.
- **Separate CMS:** two deploy jobs (web → Vercel; CMS → Fly/Docker with
  volume/db); document the CMS upgrade path in the runbook.
- **Webhooks:** CMS publish → Next revalidation endpoint (ISR) — wire and
  document.
- CI: lint → typecheck → test → build → e2e → deploy job(s) gated on
  `main`. `docs/runbook.md` adds: editor onboarding, content backup
  (db dump / CMS export), preview troubleshooting.

## 5. Test pyramid

`fullstack.md` pyramid, plus: one integration test rendering a page from
CMS fixture content, and an e2e check that a published change appears
after revalidation (against a seeded local CMS).

## 6. Release process

Code: merge to `main` → deploy (content does NOT need a code deploy —
that's the point; revalidation handles it). CMS schema changes ride code
releases; document migration order (schema before content edits).

## 7. Verification commands

```bash
npm install
docker compose up -d db        # embedded/self-hosted CMS path
npm run db:migrate && npm run seed
npm run lint && npm run typecheck && npm test
npm run build
# boot: app up + CMS admin reachable + one seeded page renders
npm start & curl -fsS http://localhost:<port>/ && curl -fsS http://localhost:<port>/admin >/dev/null && kill %1
```
