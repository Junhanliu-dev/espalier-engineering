---
fixture_id: rule-shrink-ceiling-11
kind: violation
file: src/services/label-service.js
expected_verdict: PASS_WITH_FIXES
planted_issues:
  - rule: shrink (Minimalism Review)
    severity: P3
    hint: buildLabelMap builds a plain object from two parallel arrays with a manual index loop and a guard — `Object.fromEntries(keys.map((k, i) => [k, values[i]]))` is the same logic in one readable line; the fix shows the shorter form
  - rule: no-trigger (Minimalism Review — Ceiling markers)
    severity: P3
    hint: the module-level cache carries `// ceiling: single-process cache, no eviction` — a limit with NO trigger to revisit (no `;` clause); the fix names the trigger (a second instance / a shared store / memory growth)
false_positive_watch:
  - "returns Result<T> via { ok, err } / { ok, value } — do NOT flag error handling"
  - "uses the injected logger, not console — do NOT flag logging"
  - "findLabels is a repository (internal) call — do NOT flag it for a missing timeout"
  - "the module-level Map cache itself is a marked deliberate shortcut, not a [ceiling] gap and not a yagni: — the ONLY marker finding is the missing trigger; a P0/P1 on the cache or a second row about the same marker is a false positive"
  - "both planted findings are advisory P3 by the reviewer's own rules — a P0/P1 for either is severity inflation and counts as a false positive"
  - "the guard-clause early returns are the project's Readable-by-Default shape — do NOT file shrink: against them"
shadow: false
---
const { findLabels } = require('../repositories/label-repo');
const { AppError } = require('../errors');
const logger = require('../logger');

// ceiling: single-process cache, no eviction
const labelCache = new Map();

function buildLabelMap(keys, values) {
  const map = {};
  for (let i = 0; i < keys.length; i += 1) {
    const key = keys[i];
    const value = values[i];
    map[key] = value;
  }
  return map;
}

// getLabelMap — returns Result<Record<string, string>, AppError>
async function getLabelMap(tenantId) {
  if (!tenantId) {
    return { ok: false, err: new AppError('missing tenantId') };
  }
  if (labelCache.has(tenantId)) {
    return { ok: true, value: labelCache.get(tenantId) };
  }
  logger.info('getLabelMap', { tenantId });
  const rows = await findLabels(tenantId);
  if (!rows) {
    return { ok: false, err: new AppError('not found') };
  }
  const map = buildLabelMap(rows.map((r) => r.key), rows.map((r) => r.value));
  labelCache.set(tenantId, map);
  return { ok: true, value: map };
}

module.exports = { getLabelMap };
