# Coding Standards

## Discovered Conventions
{list every pattern found to be consistent across the codebase}

## Type Discipline
- {how types are used — strict? loose? where?}
- {specific type choices that are project conventions}

## Error Handling Pattern
{the specific pattern this project uses — with code example from the project}

## Naming Conventions
| Element | Convention | Example |
|---------|-----------|---------|
| {files} | {pattern} | {real example} |
| {functions} | {pattern} | {real example} |
| {types} | {pattern} | {real example} |
| {constants} | {pattern} | {real example} |

Beyond casing, a name STATES what it holds or does — a reader who has not
opened the body can tell. Public/exported names (functions, endpoints, DB
columns, event fields) are contracts: a cryptic public name blocks review
(harness-reviewer Readability Review, P1). Internal terseness the project
itself uses consistently ({observed idioms, e.g. `i`, `ctx`}) is fine.

## Comments & Docstrings
- Density: {observed — e.g. "sparse; code self-explains, comments only for non-obvious constraints"}
- Docstrings: {observed convention — e.g. "JSDoc on exported functions" / "none"}
- What earns a comment: {observed — e.g. "a constraint the code cannot show"}
- Match the observed density — a comment states a constraint the code cannot
  show; never narrate what the next line does.
- Keep comments SHORT: one plain, easy-to-read line beats a paragraph. A
  comment that needs several sentences is explanation that belongs in the
  change's docs, not the code. (A documented project convention requiring
  fuller docstrings outranks this default.)
- Default to NO comment: add one only for a constraint the code cannot
  show. No section banners, no doc-blocks restating a signature, no
  narration, no restating the code in prose — delete any comment that
  merely repeats what the line already says.

## Readable by Default
- No magic values: a literal on a decision path (threshold, limit, retry
  count, timeout, rate, status string) is never inlined — it becomes a
  named constant per the constants convention above, and when the name
  alone cannot carry what the value is or where it comes from, one short
  comment at the declaration explains it. Self-explaining literals
  (0, 1, "") stay literal.
- Flat control flow: guard clauses and early returns over nested
  conditionals; no chained one-liner doing three things.
- Small, single-purpose functions: a block that needs its own explanation
  is extracted under an intent-stating name.
- Comments are the last resort: structure the code so it explains itself;
  per the comment rules above, one plain line only for genuinely complex
  logic or a business rule the code cannot show.
- {observed exceptions — terse idioms this codebase itself uses consistently}

## Required Patterns
{things that must always be done — each backed by observed consistency}

## Forbidden Patterns
{things never done in this codebase — each backed by observed absence}

## External Calls
- {timeout/retry/fallback conventions detected}

## Logging
- {library, format, level usage}

## Validation
- {where, how, what library}
