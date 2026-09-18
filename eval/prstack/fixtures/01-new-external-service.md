---
id: 01-new-external-service
kind: must-patch
expect:
  wiki/architecture.md: NO-IMPACT
  wiki/data-models.md: NO-IMPACT
  wiki/critical-paths.md: NO-IMPACT
  wiki/external-services.md: PATCH
  rules/coding-standards.md: NO-IMPACT
must_cite: billing/stripe_client.py
---

The diff introduces the project's first outbound call to Stripe.
`external-services.md` lists every third party the system talks to and does not
mention Stripe, so the diff makes that list false. Nothing else moved: no new
layer, no schema change, and the code follows the existing error-handling
convention rather than establishing a new one. `critical-paths.md` documents
only the registration path, which this diff does not touch — so the single
correct PATCH is `external-services.md` and every other verdict is NO-IMPACT.

## DIFF

```diff
--- /dev/null
+++ b/billing/stripe_client.py
@@ -0,0 +1,18 @@
+import os
+import httpx
+
+_BASE = "https://api.stripe.com/v1"
+
+
+def charge(customer_id: str, amount_cents: int) -> dict:
+    """Create a charge. Raises BillingError on any non-2xx."""
+    resp = httpx.post(
+        f"{_BASE}/charges",
+        auth=(os.environ["STRIPE_SECRET_KEY"], ""),
+        data={"customer": customer_id, "amount": amount_cents},
+        timeout=10.0,
+    )
+    if resp.status_code >= 300:
+        raise BillingError(f"stripe charge failed: {resp.status_code}")
+    return resp.json()
--- a/billing/service.py
+++ b/billing/service.py
@@ -12,6 +12,7 @@ from billing.models import Invoice
+from billing.stripe_client import charge
 
 
 def settle(invoice: Invoice) -> Invoice:
@@ -20,6 +21,7 @@ def settle(invoice: Invoice) -> Invoice:
     if invoice.status != "open":
         raise BillingError("invoice is not open")
+    charge(invoice.customer_id, invoice.amount_cents)
     invoice.status = "paid"
     return invoice
```

## DOCS

### wiki/architecture.md

```markdown
# Architecture

Three layers: `api/` (HTTP handlers), `billing/` and `accounts/` (services),
`storage/` (persistence). Services never import handlers; handlers never touch
`storage/` directly.
```

### wiki/data-models.md

```markdown
# Data Models

- `Invoice` — customer_id, amount_cents, status (`open` | `paid` | `void`).
- `Account` — id, email, created_at.
```

### wiki/critical-paths.md

```markdown
# Critical Paths

- Account registration: `api/accounts.py:register` → `accounts.service.register`
  → `storage.accounts.save`.
```

### wiki/external-services.md

```markdown
# External Services

- **Postgres** — primary store, reached only through `storage/`.
- **SendGrid** — transactional email, called from `accounts/notify.py`.
```

### rules/coding-standards.md

```markdown
# Coding Standards

- Raise a domain error (`BillingError`, `AccountError`) rather than returning
  `None` on failure (`billing/service.py:31`).
- Every outbound HTTP call sets an explicit timeout (`accounts/notify.py:18`).
```
