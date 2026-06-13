---
fixture_id: drift-01-stale-wiki
bucket: drift
question: how are user sessions stored
expected_type: how
expect:
  - reads espalier/wiki/architecture.md (claims in-memory sessions)
  - reads src/session/store.ts and finds it uses Redis, contradicting the doc
  - answer TRUSTS THE CODE (Redis), not the stale wiki
  - flags the wiki via mark_stale with an "ask-verify:" reason
  - surfaces a one-line "/espalier-prune" suggestion
expect_drift: true
expect_gap: false
---
=== FILE: espalier/.merge-hook-decision ===
not-needed
=== FILE: espalier/hooks/drift-helpers.sh ===
#!/bin/bash
# Minimal stand-in for the real drift-helpers.sh (eval fixture only).
_DS_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
DRIFT_STATE="$_DS_ROOT/espalier/.drift-state.tsv"
_ds_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
_ds_sanitize() { printf '%s' "$1" | tr -d '\t\n\r'; }
mark_stale() {
  local file="$1" sha="$2" reason; reason=$(_ds_sanitize "$3")
  [ -f "$_DS_ROOT/$file" ] || return 0
  touch "$DRIFT_STATE"
  local first_seen; first_seen=$(awk -F'\t' -v f="$file" '$1==f {print $3; exit}' "$DRIFT_STATE")
  [ -z "$first_seen" ] && first_seen=$(_ds_now)
  local tmp; tmp=$(mktemp "${DRIFT_STATE}.XXXXXX") || return 1
  awk -F'\t' -v f="$file" '$1!=f' "$DRIFT_STATE" > "$tmp" 2>/dev/null
  printf '%s\t%s\t%s\t%s\n' "$file" "$sha" "$first_seen" "$reason" >> "$tmp"
  mv "$tmp" "$DRIFT_STATE"
}
=== FILE: espalier/wiki/architecture.md ===
# Architecture

## Sessions
Sessions are kept in an in-process `Map` in `src/session/store.ts`. This means
sessions do not survive a server restart and are not shared across instances.
=== FILE: src/session/store.ts ===
import { createClient } from "redis";
const redis = createClient({ url: process.env.REDIS_URL });
export async function getSession(id: string) {
  return JSON.parse((await redis.get(`sess:${id}`)) ?? "null");
}
export async function putSession(id: string, data: object) {
  await redis.set(`sess:${id}`, JSON.stringify(data), { EX: 3600 });
}
