# Engineering Structure (ReviewApp — eval fixture project)

## Layers
- `controllers/` — HTTP handlers. May import `services/`. **MUST NOT** import `db`
  or a repository directly.
- `services/` — business logic. May import `repositories/`.
- `repositories/` — data access. The ONLY layer that imports `db`.

## Boundary Rule
A `controllers/` file importing `db` (or reaching a repository/`db` directly,
bypassing a service) is a **P0** layer violation.
