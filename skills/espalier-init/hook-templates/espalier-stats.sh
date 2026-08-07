#!/bin/bash
# espalier-stats.sh — read-only lane-quality report over the espalier/ audit
# chain. Run manually from the repo root:
#
#   bash espalier/hooks/espalier-stats.sh
#
# Prints markdown to stdout. Writes NOTHING. Every section degrades to a
# "none" line when its source data is absent — a fresh install reports
# honestly instead of erroring. bash-3.2 safe (no associative arrays).
#
# What it measures (the lagging quality signals the docs call Layer 3):
#   - per-lane volume + terminal-status distribution (changes/*/*/pipeline-state.md)
#   - review-round + rollback distributions (the escalation counters)
#   - grill verdict mix (GRILLED / SKIPPED: crisp / --no-grill / non-interactive)
#   - charted vs uncharted feats (requirements.md charted_from:) — code rounds,
#     rollbacks, and the fix echo (fix-lane caused_by pointing at each cohort)
#   - per-map ticket/fog/session/spawned-change state (espalier/maps/)
#   - convention divergence hotspots (conv_fold, when drift-helpers is present)

ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$ROOT" || exit 1
[ -d espalier ] || { echo "no espalier/ directory here — nothing to report"; exit 0; }

CH=espalier/changes
MAPS=espalier/maps

# _stat_dist LABEL <<< "one number per line" — min/median/mean/max, count-aware.
_stat_dist() {
  awk -v label="$1" '
    { v[++n] = $1; sum += $1 }
    END {
      if (n == 0) { printf "%s: none\n", label; exit }
      # insertion sort — n is small
      for (i = 2; i <= n; i++) { x = v[i]; j = i - 1
        while (j >= 1 && v[j] > x) { v[j+1] = v[j]; j-- } v[j+1] = x }
      med = (n % 2) ? v[(n+1)/2] : (v[n/2] + v[n/2+1]) / 2
      printf "%s: n=%d min=%s median=%s mean=%.2f max=%s\n", label, n, v[1], med, sum/n, v[n]
    }'
}

# _last_status STATEFILE — last `- Status:` value, or IN_PROGRESS-ish fallback.
_last_status() {
  awk -F': ' '/^- Status:/ { s = $2 } END { print (s == "" ? "(no status line)" : s) }' "$1"
}

echo "# Espalier Stats — $(date -u +%Y-%m-%d)"
echo

# ── Changes by lane ──────────────────────────────────────────────────────────
echo "## Changes by lane"
echo
if [ ! -d "$CH" ] || ! ls "$CH"/*/*/pipeline-state.md >/dev/null 2>&1; then
  echo "none — no changes recorded yet"
else
  for type_dir in "$CH"/*/; do
    type=$(basename "$type_dir")
    [ "$type" = "_template" ] && continue
    ls "$type_dir"*/pipeline-state.md >/dev/null 2>&1 || continue
    total=0
    statuses=""
    for sf in "$type_dir"*/pipeline-state.md; do
      total=$((total + 1))
      statuses="$statuses
$(_last_status "$sf")"
    done
    dist=$(printf '%s\n' "$statuses" | grep -v '^$' | sort | uniq -c | sort -rn \
           | awk '{ printf "%s%s=%s", (NR>1 ? " " : ""), $2, $1 }')
    echo "- **$type**: $total ($dist)"
  done
fi
echo

# ── Review rounds + rollbacks ────────────────────────────────────────────────
echo "## Review rounds + rollbacks"
echo
if [ -d "$CH" ] && ls "$CH"/*/*/pipeline-state.md >/dev/null 2>&1; then
  # `- Review Rounds: req=N/D, code=N/D, test=N/D` — numerators only.
  for kind in req code test; do
    sed -n -E "s/^- Review Rounds:.* ${kind}=([0-9]+)\/.*/\1/p" "$CH"/*/*/pipeline-state.md 2>/dev/null \
      | _stat_dist "${kind} rounds"
  done
  sed -n -E 's/^- Total Rollbacks: ([0-9]+).*/\1/p' "$CH"/*/*/pipeline-state.md 2>/dev/null \
    | _stat_dist "rollbacks"
else
  echo "none"
fi
echo

# ── Grill verdicts ───────────────────────────────────────────────────────────
echo "## Grill verdicts (Stage 1 residual-ambiguity mix)"
echo
if [ -d "$CH" ] && ls "$CH"/*/*/pipeline-state.md >/dev/null 2>&1; then
  g=$(grep -ho 'GRILLED' "$CH"/*/*/pipeline-state.md 2>/dev/null | wc -l | tr -d ' ')
  sc=$(grep -ho 'SKIPPED: crisp' "$CH"/*/*/pipeline-state.md 2>/dev/null | wc -l | tr -d ' ')
  sn=$(grep -ho 'SKIPPED: --no-grill' "$CH"/*/*/pipeline-state.md 2>/dev/null | wc -l | tr -d ' ')
  si=$(grep -ho 'SKIPPED: non-interactive' "$CH"/*/*/pipeline-state.md 2>/dev/null | wc -l | tr -d ' ')
  echo "GRILLED=$g  crisp=$sc  no-grill=$sn  non-interactive=$si"
  echo
  echo "(A map-charted slice should trend crisp/light — high GRILLED among"
  echo "charted feats means maps are under-specifying their slices.)"
else
  echo "none"
fi
echo

# ── Charted vs uncharted feats ───────────────────────────────────────────────
echo "## Charted vs uncharted feats (map-lane echo)"
echo
if [ -d "$CH/feat" ] && ls "$CH"/feat/*/pipeline-state.md >/dev/null 2>&1; then
  charted_n=0; uncharted_n=0
  charted_code=""; uncharted_code=""
  charted_rb=""; uncharted_rb=""
  charted_slugs=""
  for sf in "$CH"/feat/*/pipeline-state.md; do
    dir=$(dirname "$sf"); slug=$(basename "$dir")
    code=$(sed -n -E 's/^- Review Rounds:.* code=([0-9]+)\/.*/\1/p' "$sf" | head -1)
    rb=$(sed -n -E 's/^- Total Rollbacks: ([0-9]+).*/\1/p' "$sf" | head -1)
    if grep -q '^charted_from:' "$dir/requirements.md" 2>/dev/null; then
      charted_n=$((charted_n + 1))
      charted_slugs="$charted_slugs $slug"
      [ -n "$code" ] && charted_code="$charted_code
$code"
      [ -n "$rb" ] && charted_rb="$charted_rb
$rb"
    else
      uncharted_n=$((uncharted_n + 1))
      [ -n "$code" ] && uncharted_code="$uncharted_code
$code"
      [ -n "$rb" ] && uncharted_rb="$uncharted_rb
$rb"
    fi
  done
  echo "charted feats:   $charted_n"
  echo "uncharted feats: $uncharted_n"
  printf '%s\n' "$charted_code"   | grep -v '^$' | _stat_dist "  charted code rounds"
  printf '%s\n' "$uncharted_code" | grep -v '^$' | _stat_dist "  uncharted code rounds"
  printf '%s\n' "$charted_rb"     | grep -v '^$' | _stat_dist "  charted rollbacks"
  printf '%s\n' "$uncharted_rb"   | grep -v '^$' | _stat_dist "  uncharted rollbacks"

  # Fix echo: each fix change's caused_by target lands in one cohort.
  fix_charted=0; fix_uncharted=0; fix_unlinked=0
  if [ -d "$CH/fix" ] && ls "$CH"/fix/*/requirements.md >/dev/null 2>&1; then
    for rf in "$CH"/fix/*/requirements.md; do
      target=$(sed -n -E 's/^caused_by:[[:space:]]*(.+)$/\1/p' "$rf" | head -1 | tr -d ' ')
      if [ -z "$target" ]; then
        fix_unlinked=$((fix_unlinked + 1)); continue
      fi
      tslug=$(basename "$target")
      case " $charted_slugs " in
        *" $tslug "*) fix_charted=$((fix_charted + 1)) ;;
        *)            fix_uncharted=$((fix_uncharted + 1)) ;;
      esac
    done
  fi
  echo "  fix echo: against-charted=$fix_charted against-uncharted=$fix_uncharted unlinked=$fix_unlinked"
  echo "  (normalize by cohort size before comparing — charted=$charted_n uncharted=$uncharted_n)"
else
  echo "none — no feat changes yet"
fi
echo

# ── Maps ─────────────────────────────────────────────────────────────────────
echo "## Maps"
echo
if [ ! -d "$MAPS" ] || ! ls "$MAPS"/*/map.md >/dev/null 2>&1; then
  echo "none — no maps charted yet"
else
  for mf in "$MAPS"/*/map.md; do
    mdir=$(dirname "$mf"); mslug=$(basename "$mdir")
    mstatus=$(sed -n -E 's/^status:[[:space:]]*([A-Z_]+).*/\1/p' "$mf" | head -1)
    t_open=0; t_closed=0; t_oos=0
    g_n=0; r_n=0; p_n=0; k_n=0
    if ls "$mdir"/tickets/*.md >/dev/null 2>&1; then
      for tf in "$mdir"/tickets/*.md; do
        st=$(sed -n -E 's/^status:[[:space:]]*([a-z-]+).*/\1/p' "$tf" | head -1)
        ty=$(sed -n -E 's/^type:[[:space:]]*([a-z]+).*/\1/p' "$tf" | head -1)
        case "$st" in
          open)          t_open=$((t_open + 1)) ;;
          closed)        t_closed=$((t_closed + 1)) ;;
          out-of-scope)  t_oos=$((t_oos + 1)) ;;
        esac
        case "$ty" in
          grilling)  g_n=$((g_n + 1)) ;;
          research)  r_n=$((r_n + 1)) ;;
          prototype) p_n=$((p_n + 1)) ;;
          task)      k_n=$((k_n + 1)) ;;
        esac
      done
    fi
    # Session-log rows: table lines between "## Session log" and the next "##",
    # minus the header + separator.
    sessions=$(awk '/^## Session log/{f=1; next} /^## /{f=0} f && /^\|/' "$mf" | tail -n +3 | grep -c . || true)
    # Fog: non-empty, non-comment lines in "## Not yet specified".
    fog=$(awk '/^## Not yet specified/{f=1; next} /^## /{f=0} f && !/^<!--/ && !/^-->/ && NF' "$mf" | grep -c . || true)
    spawned=$(awk '/^## Spawned Changes/{f=1; next} /^## /{f=0} f && /^\|/' "$mf" | tail -n +3 | grep -c . || true)
    echo "- **$mslug** [$mstatus] tickets: open=$t_open closed=$t_closed out-of-scope=$t_oos" \
         "(grilling=$g_n research=$r_n prototype=$p_n task=$k_n) sessions=$sessions fog-remaining=$fog spawned=$spawned"
  done
  echo
  echo "(Quality reads: fog-remaining should shrink across sessions; a CLEARED"
  echo "map with spawned rows still open is mid-build; closed-per-session near 1"
  echo "means the one-ticket rule held.)"
fi
echo

# ── Convention divergence ────────────────────────────────────────────────────
echo "## Convention divergence (top keys)"
echo
if [ -f espalier/hooks/drift-helpers.sh ]; then
  . espalier/hooks/drift-helpers.sh
  if type conv_fold >/dev/null 2>&1; then
    out=$(conv_fold 2>/dev/null | sort -t"$(printf '\t')" -k2,2rn | head -5 \
          | awk -F'\t' '{ printf "- %s: diverges=%s status=%s\n", $1, $2, $3 }')
    if [ -n "$out" ]; then
      printf '%s\n' "$out"
      echo
      echo "(On a greenfield install, early divergence against decided rules is"
      echo "the system converging — watch that counts fall, not that they are zero.)"
    else
      echo "none recorded"
    fi
  else
    echo "drift-helpers present but conv_fold missing (pre-v0.16 install)"
  fi
else
  echo "drift-helpers not installed"
fi
