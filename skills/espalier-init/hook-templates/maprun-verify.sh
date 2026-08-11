#!/usr/bin/env bash
# maprun-verify.sh — integration verification on the assembled branch.
#
#   maprun-verify.sh <map-dir>
#
# Every ticket already built, linted, tested and passed a review panel ON ITS
# OWN. This checks the thing none of them could: that the union of them all is
# coherent. It is the difference between "each part works" and "the system works".
#
# What runs comes from plan.json `verify`:
#   "verify": {
#     "commands":            [{"name": "backend build", "dir": "backend", "run": "npm run build"}, …],
#     "clean_after_build":   ["backend/schema.prisma", …],       # generated files that must not drift
#     "forbidden_patterns":  [{"name": "no allowAll survivors",
#                              "pattern": "access: allowAll", "path": "backend/schemas/"}, …],
#     "expected_registrations": {"file": "backend/schemas/index.ts",
#                                "pattern": "^\\s*[A-Za-z]+:", "min": 26}
#   }
# Absent keys are skipped. Writes <map>/plan/verify-report.md; exits non-zero
# on any failure.
set -uo pipefail

MAP_DIR="${1:?usage: maprun-verify.sh <map-dir>}"
MAP_DIR="$(cd "$MAP_DIR" && pwd)"
PLAN="$MAP_DIR/plan/plan.json"
REPO="$(git rev-parse --show-toplevel)"
REPORT="$MAP_DIR/plan/verify-report.md"
[ -f "$PLAN" ] || { echo "verify: no plan.json at $PLAN"; exit 1; }

get() { PLAN="$PLAN" F="$1" python3 -c 'import json,os;v=json.load(open(os.environ["PLAN"])).get(os.environ["F"],"");print("" if v is None else v)'; }
vrows() { # vrows <verify-subkey> <field1,field2,...>
  PLAN="$PLAN" K="$1" FIELDS="$2" python3 - << 'PYR'
import json, os
p = json.load(open(os.environ["PLAN"]))
v = p.get("verify") or {}
fields = os.environ["FIELDS"].split(",")
for item in (v.get(os.environ["K"]) or []):
    if isinstance(item, str):
        print(item)
    else:
        print("\t".join(str(item.get(f, "")) for f in fields))
PYR
}

INTEGRATION="$(get integration_branch)"
BASE="$(get base_branch)"

# Refuse to "verify" a branch nothing was merged into — a bare integration
# branch equals the base and would false-PASS every check.
if ! git -C "$REPO" show-ref --verify --quiet "refs/heads/$INTEGRATION"; then
  echo "verify: integration branch $INTEGRATION does not exist — nothing merged yet"; exit 1
fi
AHEAD="$(git -C "$REPO" rev-list --count "$BASE..$INTEGRATION" 2>/dev/null || echo 0)"
if [ "${AHEAD:-0}" = "0" ]; then
  echo "verify: $INTEGRATION has no commits beyond $BASE — nothing merged yet"; exit 1
fi

IWT="$(bash "$REPO/espalier/hooks/maprun-integration.sh" "$MAP_DIR")"

FAILED=0
{
  echo "# Integration verification"
  echo
  echo "- Branch: \`$INTEGRATION\`"
  echo "- Worktree: \`$IWT\`"
  echo "- Head: \`$(git -C "$IWT" rev-parse --short HEAD)\`"
  echo "- Run at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "| Check | Result |"
  echo "|---|---|"
} > "$REPORT"

pass() { echo "| $1 | PASS |" >> "$REPORT"; echo "  PASS  $1"; }
fail() { echo "| $1 | **FAIL** |" >> "$REPORT"; echo "  FAIL  $1"; FAILED=1; }

echo "verify: $INTEGRATION @ $(git -C "$IWT" rev-parse --short HEAD)"

# 1. declared build/test commands
while IFS=$'\t' read -r name dir runcmd; do
  [ -n "$name" ] || continue
  if ( cd "$IWT/${dir:-.}" && bash -c "$runcmd" ) >/dev/null 2>&1; then
    pass "$name"
  else
    fail "$name"
  fi
done < <(vrows commands name,dir,run)

# 2. generated files that must not drift after the builds
while IFS= read -r path; do
  [ -n "$path" ] || continue
  [ -f "$IWT/$path" ] || continue
  if git -C "$IWT" diff --quiet -- "$path"; then
    pass "$path current"
  else
    fail "$path stale (build regenerated it)"
  fi
done < <(vrows clean_after_build path)

# 3. forbidden patterns (scaffold defaults that must not survive)
while IFS=$'\t' read -r name pattern path; do
  [ -n "$name" ] || continue
  STRAY="$(grep -rl "$pattern" "$IWT/$path" 2>/dev/null || true)"
  if [ -z "$STRAY" ]; then
    pass "$name"
  else
    fail "$name"
    { echo; echo "Files still matching \`$pattern\`:";
      echo "$STRAY" | sed "s|$IWT/|- \`|;s|\$|\`|"; } >> "$REPORT"
    echo "$STRAY" | sed 's/^/        /'
  fi
done < <(vrows forbidden_patterns name,pattern,path)

# 4. expected registrations (e.g. every schema list registered in the index)
REG="$(PLAN="$PLAN" python3 -c '
import json, os
v = (json.load(open(os.environ["PLAN"])).get("verify") or {}).get("expected_registrations") or {}
print("\t".join(str(v.get(k, "")) for k in ("file", "pattern", "min")))
')"
IFS=$'\t' read -r REG_FILE REG_PAT REG_MIN <<< "$REG"
if [ -n "$REG_FILE" ] && [ -n "$REG_MIN" ] && [ "$REG_MIN" != "0" ] && [ -f "$IWT/$REG_FILE" ]; then
  ACTUAL="$(grep -cE "$REG_PAT" "$IWT/$REG_FILE" 2>/dev/null || echo 0)"
  if [ "$ACTUAL" -ge "$REG_MIN" ]; then
    pass "registrations ($ACTUAL/$REG_MIN) in $REG_FILE"
  else
    fail "registrations ($ACTUAL/$REG_MIN) in $REG_FILE"
  fi
fi

{
  echo
  if [ "$FAILED" = "0" ]; then
    echo "**VERDICT: PASS** — the assembled branch is coherent."
  else
    echo "**VERDICT: FAIL** — see the failures above. The run does not report"
    echo "COMPLETE until this passes."
  fi
} >> "$REPORT"

echo "verify: report → $REPORT"
exit "$FAILED"
