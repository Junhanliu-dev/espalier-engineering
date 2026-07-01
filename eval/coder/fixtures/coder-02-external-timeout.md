---
fixture_id: coder-02-external-timeout
kind: task
target_file: src/services/geo-service.js
must_follow:
  - the external HTTP call includes an explicit timeout (TIMEOUT_MS / AbortController)
  - returns Result<T, AppError> and never throws
  - uses the injected logger
must_not:
  - creates or modifies files under controllers/ or repositories/
  - adds behavior beyond the lookup
shadow: false
---
Add a `lookupCity(ip)` function to a new geo service. It calls the external
geolocation API at `https://geo.example.com/lookup?ip=<ip>` and returns the city
name as an `ok` Result, or an `err` Result on failure. Follow the project's
convention for external calls.
