---
id: 04-no-impact
kind: must-be-silent
expect:
  wiki/architecture.md: NO-IMPACT
  wiki/data-models.md: NO-IMPACT
  wiki/critical-paths.md: NO-IMPACT
  wiki/external-services.md: NO-IMPACT
  rules/coding-standards.md: NO-IMPACT
---

A real source change that falsifies nothing: a bounds check added inside an
existing function, on an existing path, following the rules already written.
The docs are thin enough to look improvable and the diff is substantial enough
to feel like it deserves a doc update. Both are traps. Silence is the only
passing answer, and it is the hardest one for a model asked to look for work.

## DIFF

```diff
--- a/billing/service.py
+++ b/billing/service.py
@@ -18,9 +18,13 @@ def settle(invoice: Invoice) -> Invoice:
     """Settle an open invoice."""
     if invoice.status != "open":
         raise BillingError("invoice is not open")
+    if invoice.amount_cents <= 0:
+        raise BillingError("invoice amount must be positive")
+    if invoice.amount_cents > 100_000_00:
+        raise BillingError("invoice exceeds the settlement ceiling")
     invoice.status = "paid"
     storage.invoices.save(invoice)
     return invoice
```

## DOCS

### wiki/architecture.md

```markdown
# Architecture

Three layers: `api/` (HTTP handlers), `billing/` and `accounts/` (services),
`storage/` (persistence). Services never import handlers.
```

### wiki/data-models.md

```markdown
# Data Models

- `Invoice` — customer_id, amount_cents, status (`open` | `paid` | `void`).
```

### wiki/critical-paths.md

```markdown
# Critical Paths

- Invoice settlement: `api/invoices.py:settle` → `billing.service.settle` →
  `storage.invoices.save`.
```

### wiki/external-services.md

```markdown
# External Services

- **Postgres** — primary store, reached only through `storage/`.
```

### rules/coding-standards.md

```markdown
# Coding Standards

- Raise a domain error (`BillingError`, `AccountError`) rather than returning
  `None` on failure.
- Validate inputs at the service boundary, not in the handler.
```
