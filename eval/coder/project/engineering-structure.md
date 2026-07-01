# Engineering Structure (CoderApp — eval fixture project)

## Layers
- `controllers/` — HTTP handlers; import `services/`; never `db`/repositories.
- `services/` — business logic; import `repositories/`.
- `repositories/` — the only layer that imports `db`.
