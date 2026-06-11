#!/usr/bin/env bash
# Scripted scaffold assertions per core track — the regression net for
# scaffolder drift. No LLM. Scaffolds each requested track's default stack
# in a temp dir, runs its verification-gate essentials, and asserts no
# secret-shaped strings landed in any written file.
#
# Usage: scaffold-asserts.sh all | frontend backend fullstack mobile
# Requires network; skips tracks whose toolchain is missing (reports SKIP).
# Bash 3.2 compatible (macOS); BSD tools only.
set -uo pipefail

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0; SKIP=0
summary=""

note() { summary="${summary}$1\n"; echo "$1"; }

secret_scan() {
  # $1 = dir. Fails if anything secret-shaped is committed-to-be.
  # Heuristic: real-looking key material, not placeholder names.
  grep -rE '(sk-[A-Za-z0-9]{20,}|AKIA[A-Z0-9]{16}|-----BEGIN (RSA |EC )?PRIVATE KEY|password[[:space:]]*=[[:space:]]*['\''"][^'\''"$<{]+['\''"])' \
    --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=.dart_tool \
    --exclude-dir=.venv --exclude-dir=venv --exclude-dir=vendor \
    --exclude-dir=.next --exclude-dir=dist --exclude-dir=build \
    "$1" 2>/dev/null && return 1 || return 0
}

run_frontend() {
  command -v npm >/dev/null || { note "frontend: SKIP (no npm)"; SKIP=$((SKIP+1)); return; }
  local d="$WORK/frontend"
  if (mkdir -p "$d" && cd "$d" \
      && npm create vite@latest app -- --template react-ts >log 2>&1 \
      && cd app && npm install --no-audit --no-fund >>../log 2>&1 \
      && npm run build >>../log 2>&1 \
      && [ -f package.json ] && [ -d dist ] \
      && secret_scan .); then
    note "frontend: PASS"; PASS=$((PASS+1))
  else
    note "frontend: FAIL (see $d/log)"; tail -15 "$d/log" 2>/dev/null; FAIL=$((FAIL+1))
  fi
}

run_backend() {
  command -v uv >/dev/null || { note "backend: SKIP (no uv)"; SKIP=$((SKIP+1)); return; }
  local d="$WORK/backend"
  if (mkdir -p "$d" && cd "$d" \
      && uv init --name app >log 2>&1 \
      && uv add fastapi uvicorn >>log 2>&1 \
      && printf 'from fastapi import FastAPI\napp = FastAPI()\n\n@app.get("/healthz")\ndef healthz():\n    return {"ok": True}\n' > main.py \
      && (uv run uvicorn main:app --port 8971 >>log 2>&1 &) && sleep 3 \
      && curl -fsS http://localhost:8971/healthz >/dev/null \
      && secret_scan .); then
    pkill -f "uvicorn main:app" 2>/dev/null
    note "backend: PASS"; PASS=$((PASS+1))
  else
    pkill -f "uvicorn main:app" 2>/dev/null
    note "backend: FAIL (see $d/log)"; tail -15 "$d/log" 2>/dev/null; FAIL=$((FAIL+1))
  fi
}

run_fullstack() {
  command -v npx >/dev/null || { note "fullstack: SKIP (no npx)"; SKIP=$((SKIP+1)); return; }
  local d="$WORK/fullstack"
  if (mkdir -p "$d" && cd "$d" \
      && npx --yes create-next-app@latest app --ts --eslint --tailwind --app \
           --no-src-dir --import-alias "@/*" --use-npm --turbopack >log 2>&1 \
      && cd app && npm run build >>../log 2>&1 \
      && { [ -f next.config.ts ] || [ -f next.config.mjs ] || [ -f next.config.js ]; } \
      && secret_scan .); then
    note "fullstack: PASS"; PASS=$((PASS+1))
  else
    note "fullstack: FAIL (see $d/log)"; tail -15 "$d/log" 2>/dev/null; FAIL=$((FAIL+1))
  fi
}

run_mobile() {
  command -v flutter >/dev/null || { note "mobile: SKIP (no flutter)"; SKIP=$((SKIP+1)); return; }
  local d="$WORK/mobile"
  if (mkdir -p "$d" && cd "$d" \
      && flutter create --org com.eval app >log 2>&1 \
      && cd app && flutter analyze >>../log 2>&1 && flutter test >>../log 2>&1 \
      && secret_scan .); then
    note "mobile: PASS"; PASS=$((PASS+1))
  else
    note "mobile: FAIL (see $d/log)"; tail -15 "$d/log" 2>/dev/null; FAIL=$((FAIL+1))
  fi
}

tracks="${*:-}"
[ "$tracks" = "all" ] || [ -z "$tracks" ] && tracks="frontend backend fullstack mobile"
for t in $tracks; do
  case "$t" in
    frontend)  run_frontend ;;
    backend)   run_backend ;;
    fullstack) run_fullstack ;;
    mobile)    run_mobile ;;
    *) note "$t: unknown track (core 4 only)"; FAIL=$((FAIL+1)) ;;
  esac
done

echo
printf '%b' "$summary"
echo "pass=$PASS fail=$FAIL skip=$SKIP"
[ "$FAIL" -eq 0 ] || exit 1
