---
fixture_id: collision-03-order-field-ripple
mode: spec
expected_tier: light
# Text signals ~1. Tier floored to light by the Step 1.5 unstated ripple: critical-paths.md
# documents Order feeding three consumers (invoicing, analytics export, receipt email). The
# requirement adds a field but says nothing about whether those consumers use it — the
# collision is surfaced only if grill cites critical-paths and asks which consume it.
expected_signals: 1
coverage_only: true
planted_ambiguities: []
planted_collisions:
  - doc: wiki/critical-paths.md#order-lifecycle
    kind: unstated-ripple
    resolves_to: decide, per documented consumer (invoicing, analytics, receipt), whether each reads discountCode
answer_script:
  - asks_about: critical-paths shows Order feeds invoicing, analytics, and the receipt email — which consume discountCode
    reply: invoicing applies it to the total, analytics exports it as a column, and the receipt email shows it — all three, this release
shadow: false
---
feat: add a discountCode field to the Order model

## MOCK CONTEXT

The following is the entire `espalier/rules/` and `espalier/wiki/` for this project.

### espalier/wiki/critical-paths.md

```markdown
# Critical Paths

## Order lifecycle
When an Order is created or updated it fans out to three downstream consumers:
1. **Invoicing** (`src/invoicing/`) — computes the payable total from Order fields.
2. **Analytics export** (`src/analytics/orderExport.ts`) — flattens the Order into the
   nightly CSV; each Order field becomes a column.
3. **Receipt email** (`src/mail/receipt.ts`) — renders the customer-facing receipt from
   Order fields.
A new Order field is invisible to a consumer until that consumer is updated to read it —
adding a field without touching these three is a silent no-op for each.
```

### espalier/wiki/data-models.md

```markdown
# Data Models

## Order
Fields: `id`, `customerId`, `lineItems`, `subtotal`, `total`, `createdAt`. Persisted in the
`orders` table. Consumed by invoicing, analytics export, and the receipt email (see
critical-paths.md#order-lifecycle).
```
