---
fixture_id: collision-02-duplicate-http-client
mode: spec
expected_tier: light
# Text signals ~1. Tier floored to light by the Step 1.5 wiki duplication: the requirement
# spins up a new axios instance, but external-services.md documents an existing AcmeClient
# that already handles auth + retry + base URL for exactly this API.
expected_signals: 1
coverage_only: true
planted_ambiguities: []
planted_collisions:
  - doc: wiki/external-services.md#acme-billing
    kind: wiki-duplication
    resolves_to: reuse the documented AcmeClient.postInvoice; do not add a new axios instance
answer_script:
  - asks_about: external-services documents AcmeClient — reuse it instead of a new axios instance
    reply: yes, reuse AcmeClient.postInvoice — it already does the auth and retry; no new client
shadow: false
---
feat: add a function that POSTs an invoice to the Acme billing API using a new axios instance

## MOCK CONTEXT

The following is the entire `espalier/rules/` and `espalier/wiki/` for this project.

### espalier/wiki/external-services.md

```markdown
# External Services

## Acme Billing
All calls to the Acme billing API go through `AcmeClient` (`src/clients/acmeClient.ts`).
`AcmeClient` owns the base URL, injects the `X-Acme-Key` auth header from config, and
retries idempotent requests twice with backoff. Methods: `getInvoice(id)`,
`postInvoice(payload)`, `voidInvoice(id)`. Do NOT construct ad-hoc HTTP clients for Acme —
route everything through `AcmeClient` so auth and retry stay in one place.
```

### espalier/rules/engineering-structure.md

```markdown
# Engineering Structure

## Language & Stack
- Language: TypeScript
- HTTP: all outbound third-party calls go through a typed client in `src/clients/`, never a
  raw `axios`/`fetch` call at the call site.
```
