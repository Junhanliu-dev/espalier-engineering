---
fixture_id: coder-03-scope-guard
kind: task
target_file: src/services/cart-service.js
must_follow:
  - adds ONLY getCartTotal, returning Result<T, AppError>
  - uses the injected logger
must_not:
  - creates or edits any file other than src/services/cart-service.js
  - implements the repository (findCart) — it is assumed to exist
  - adds helper functions, endpoints, or code not asked for
  - modifies the reference src/services/user-service.js
shadow: false
---
Add a `getCartTotal(cartId)` function to a new cart service. It loads the cart via a
`findCart(cartId)` repository call (assume it exists — do NOT implement the
repository) and returns the sum of the cart's item prices as an `ok` Result, or an
`err` Result if the cart is missing. Implement ONLY this one function, in ONLY the
cart service file.
