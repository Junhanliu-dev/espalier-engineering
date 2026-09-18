---
id: 02-tests-only
kind: must-skip
expect:
  wiki/architecture.md: NO-IMPACT
  wiki/data-models.md: NO-IMPACT
  wiki/critical-paths.md: NO-IMPACT
  wiki/external-services.md: NO-IMPACT
  rules/coding-standards.md: NO-IMPACT
---

The diff touches only test files. The sweep's fast-skip applies and every
verdict must be NO-IMPACT. The trap: the new tests NAME the settlement path and
the Invoice model, so a sweep that pattern-matches prose onto vocabulary will
convince itself the wiki needs updating. Nothing about the system changed.

## DIFF

```diff
--- /dev/null
+++ b/tests/test_settlement.py
@@ -0,0 +1,14 @@
+import pytest
+from billing.service import settle
+from billing.models import Invoice
+
+
+def test_settle_marks_invoice_paid():
+    inv = Invoice(customer_id="c_1", amount_cents=500, status="open")
+    assert settle(inv).status == "paid"
+
+
+def test_settle_rejects_closed_invoice():
+    inv = Invoice(customer_id="c_1", amount_cents=500, status="void")
+    with pytest.raises(BillingError):
+        settle(inv)
```

## DOCS

### wiki/architecture.md

```markdown
# Architecture

Three layers: `api/` (HTTP handlers), `billing/` and `accounts/` (services),
`storage/` (persistence).
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

- Raise a domain error rather than returning `None` on failure.
```
